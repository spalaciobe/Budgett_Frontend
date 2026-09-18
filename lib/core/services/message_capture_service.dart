import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';

import 'package:budgett_frontend/data/models/captured_message_model.dart';

/// Everything the capture pipeline needs from the platform: permission state,
/// the native configuration, and the queue of messages the notification
/// listener and SMS receiver wrote while the app was closed.
///
/// Android-only. Every call is a no-op elsewhere so the rest of the app (web,
/// Windows, macOS) keeps working without platform checks at each call site.
class CaptureStatus {
  /// Master switch, as stored natively.
  final bool enabled;
  final bool smsEnabled;
  final bool locationEnabled;

  /// Special access granted in system settings — no runtime dialog exists.
  final bool notificationAccess;
  final bool smsPermission;
  final bool locationPermission;

  /// Required for the GPS fix, because it is taken with the app closed.
  final bool backgroundLocationPermission;

  /// Messages waiting in the native queue.
  final int queued;

  /// False on every platform but Android.
  final bool isSupported;

  const CaptureStatus({
    this.enabled = false,
    this.smsEnabled = false,
    this.locationEnabled = false,
    this.notificationAccess = false,
    this.smsPermission = false,
    this.locationPermission = false,
    this.backgroundLocationPermission = false,
    this.queued = 0,
    this.isSupported = false,
  });

  static const unsupported = CaptureStatus();

  /// True when at least one source can actually deliver messages.
  bool get canCapture =>
      enabled && (notificationAccess || (smsEnabled && smsPermission));

  /// True when a captured payment will carry coordinates.
  bool get canCaptureLocation =>
      locationEnabled && backgroundLocationPermission;

  /// Short list of what still has to be granted, for the settings screen.
  List<String> get missingGrants => [
        if (!notificationAccess) 'Notification access',
        if (smsEnabled && !smsPermission) 'SMS permission',
        if (locationEnabled && !backgroundLocationPermission)
          'Background location',
      ];

  factory CaptureStatus.fromPlatform(Map<dynamic, dynamic> map) => CaptureStatus(
        enabled: map['enabled'] as bool? ?? false,
        smsEnabled: map['smsEnabled'] as bool? ?? false,
        locationEnabled: map['locationEnabled'] as bool? ?? false,
        notificationAccess: map['notificationAccess'] as bool? ?? false,
        smsPermission: map['smsPermission'] as bool? ?? false,
        locationPermission: map['locationPermission'] as bool? ?? false,
        backgroundLocationPermission:
            map['backgroundLocationPermission'] as bool? ?? false,
        queued: (map['queued'] as num?)?.toInt() ?? 0,
        isSupported: true,
      );
}

/// The slice of the platform that the ingest pipeline depends on.
///
/// Extracted as an interface so ingestion can be driven in tests with a list
/// of canned messages instead of a MethodChannel.
abstract class CapturePlatform {
  /// Takes every queued message and clears the queue.
  Future<List<RawCapture>> drain();

  /// Turns coordinates into a short human label, or null when unavailable.
  Future<String?> describeLocation(double latitude, double longitude);
}

class MessageCaptureService implements CapturePlatform {
  static final MessageCaptureService _instance =
      MessageCaptureService._internal();

  factory MessageCaptureService() => _instance;

  MessageCaptureService._internal();

  static const _channel = MethodChannel('budgett/message_capture');

  /// Notification listening and SMS receiving only exist on Android.
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<CaptureStatus> getStatus() async {
    if (!isSupported) return CaptureStatus.unsupported;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getStatus',
      );
      if (result == null) return CaptureStatus.unsupported;
      return CaptureStatus.fromPlatform(result);
    } on PlatformException catch (e) {
      debugPrint('Capture status failed: ${e.message}');
      return CaptureStatus.unsupported;
    } on MissingPluginException {
      return CaptureStatus.unsupported;
    }
  }

  /// Pushes configuration into the native components. They read it on every
  /// message, so a change takes effect immediately without a restart.
  Future<CaptureStatus> applyConfig({
    bool? enabled,
    bool? smsEnabled,
    bool? locationEnabled,
    List<String>? blockedSources,
    List<String>? allowedSources,
  }) async {
    if (!isSupported) return CaptureStatus.unsupported;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'applyConfig',
        <String, dynamic>{
          if (enabled != null) 'enabled': enabled,
          if (smsEnabled != null) 'smsEnabled': smsEnabled,
          if (locationEnabled != null) 'locationEnabled': locationEnabled,
          if (blockedSources != null) 'blockedSources': blockedSources,
          if (allowedSources != null) 'allowedSources': allowedSources,
        },
      );
      if (result == null) return CaptureStatus.unsupported;
      return CaptureStatus.fromPlatform(result);
    } on PlatformException catch (e) {
      debugPrint('Capture config failed: ${e.message}');
      return CaptureStatus.unsupported;
    } on MissingPluginException {
      return CaptureStatus.unsupported;
    }
  }

  /// Takes every queued message and clears the queue. Messages already stored
  /// in Supabase are filtered out by fingerprint further up the pipeline, so a
  /// crash between the drain and the insert costs at most one batch.
  @override
  Future<List<RawCapture>> drain() async {
    if (!isSupported) return const [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('drain');
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(RawCapture.fromPlatform)
          .toList();
    } on PlatformException catch (e) {
      debugPrint('Capture drain failed: ${e.message}');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<int> queuedCount() async {
    if (!isSupported) return 0;
    try {
      return await _channel.invokeMethod<int>('queuedCount') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Opens the system screen where notification access is granted. There is no
  /// runtime permission dialog for it.
  Future<void> openNotificationAccessSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('openNotificationAccessSettings');
    } catch (e) {
      debugPrint('Could not open notification access settings: $e');
    }
  }

  // ─── runtime permissions ───────────────────────────────────────────────────

  /// Requests RECEIVE_SMS. Handled natively so permission reading and
  /// requesting stay in one place.
  Future<bool> requestSmsPermission() =>
      _requestBool('requestSmsPermission');

  /// Requests location in the two steps Android requires: the foreground grant
  /// first, then "Allow all the time". Asking for background straight away is
  /// rejected outright on Android 11+.
  ///
  /// Returns false when the background grant is still missing — which is the
  /// normal outcome on Android 11+, where it can only be given in app
  /// settings. Callers should then offer [openSystemAppSettings].
  Future<bool> requestBackgroundLocation() async {
    if (!isSupported) return false;
    final foreground = await _requestBool('requestLocationPermission');
    if (!foreground) return false;
    return _requestBool('requestBackgroundLocation');
  }

  /// Opens this app's system settings page, where a permission the dialog
  /// cannot grant (background location) can be changed.
  Future<void> openSystemAppSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('openAppSettings');
    } catch (e) {
      debugPrint('Could not open app settings: $e');
    }
  }

  Future<bool> _requestBool(String method) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (e) {
      debugPrint('Permission request $method failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  // ─── reverse geocoding ─────────────────────────────────────────────────────

  /// Turns coordinates into a short human label ("Calle 80 #45-12, Bogotá").
  ///
  /// Best effort: the platform geocoder is rate-limited and offline-unavailable,
  /// so a failure returns null and the capture keeps its raw coordinates.
  @override
  Future<String?> describeLocation(double latitude, double longitude) async {
    if (kIsWeb) return null;
    try {
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;

      // Street NAME only. `subThoroughfare` is the house number, which is
      // noise for "where did I pay" and is also what the geocoder echoes back
      // in `name`, producing labels like "25b-15, Carrera 63 25b-15, …".
      final street = (p.thoroughfare?.trim().isNotEmpty ?? false)
          ? p.thoroughfare!.trim()
          : (p.name?.trim() ?? '');

      final parts = <String>[
        if (street.isNotEmpty) street,
        if (p.subLocality?.trim().isNotEmpty ?? false) p.subLocality!.trim(),
        if (p.locality?.trim().isNotEmpty ?? false) p.locality!.trim(),
      ];

      // Drop any part already contained in another — geocoders repeat
      // themselves, and equality alone does not catch "25b-15" inside
      // "Carrera 63 25b-15".
      final kept = <String>[];
      for (final part in parts) {
        final lower = part.toLowerCase();
        final redundant = kept.any((k) =>
            k.toLowerCase().contains(lower) || lower.contains(k.toLowerCase()));
        if (!redundant) kept.add(part);
      }

      final label = kept.join(', ');
      return label.isEmpty ? null : label;
    } catch (e) {
      debugPrint('Reverse geocoding failed: $e');
      return null;
    }
  }
}
