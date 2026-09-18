/// A channel that has sent us at least one message: an Android app (by package
/// name) or an SMS sender.
///
/// Holds the user's override of the source name — renaming
/// `com.bancolombia.olimpia` to "Bancolombia" once makes every message from it
/// show that name from then on.
class CaptureSource {
  final String id;
  final String channel; // notification | sms
  final String sourceKey; // package name or SMS sender
  final String? detectedName; // app label / raw sender, as reported by Android
  final String? displayName; // user override
  final String? issuerKey;
  final String? defaultAccountId;
  final bool isEnabled;
  final int messageCount;
  final DateTime? lastSeenAt;

  const CaptureSource({
    required this.id,
    required this.channel,
    required this.sourceKey,
    this.detectedName,
    this.displayName,
    this.issuerKey,
    this.defaultAccountId,
    this.isEnabled = true,
    this.messageCount = 0,
    this.lastSeenAt,
  });

  /// What the UI shows. The override wins, then what Android reported, then
  /// the raw key as a last resort.
  String get effectiveName {
    final override = displayName?.trim();
    if (override != null && override.isNotEmpty) return override;
    final detected = detectedName?.trim();
    if (detected != null && detected.isNotEmpty) return detected;
    return sourceKey;
  }

  bool get hasOverride => (displayName?.trim().isNotEmpty ?? false);

  bool get isSms => channel == 'sms';

  factory CaptureSource.fromJson(Map<String, dynamic> json) => CaptureSource(
        id: json['id'] as String,
        channel: json['channel'] as String,
        sourceKey: json['source_key'] as String,
        detectedName: json['detected_name'] as String?,
        displayName: json['display_name'] as String?,
        issuerKey: json['issuer_key'] as String?,
        defaultAccountId: json['default_account_id'] as String?,
        isEnabled: (json['is_enabled'] as bool?) ?? true,
        messageCount: (json['message_count'] as int?) ?? 0,
        lastSeenAt: json['last_seen_at'] != null
            ? DateTime.parse(json['last_seen_at'] as String).toLocal()
            : null,
      );

  CaptureSource copyWith({
    String? displayName,
    String? issuerKey,
    String? defaultAccountId,
    bool? isEnabled,
  }) =>
      CaptureSource(
        id: id,
        channel: channel,
        sourceKey: sourceKey,
        detectedName: detectedName,
        displayName: displayName ?? this.displayName,
        issuerKey: issuerKey ?? this.issuerKey,
        defaultAccountId: defaultAccountId ?? this.defaultAccountId,
        isEnabled: isEnabled ?? this.isEnabled,
        messageCount: messageCount,
        lastSeenAt: lastSeenAt,
      );
}
