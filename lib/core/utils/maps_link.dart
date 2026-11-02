import 'package:url_launcher/url_launcher.dart';

/// Google Maps URL that drops a pin on the exact coordinates.
///
/// Built from the raw fix rather than the address label: the label is a
/// reverse-geocoded approximation, the coordinates are what was measured.
Uri mapsUri(double latitude, double longitude) => Uri.https(
      'www.google.com',
      '/maps/search/',
      {
        'api': '1',
        'query': '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}',
      },
    );

/// Opens the coordinates in the Maps app, or the browser when there is none.
/// Returns false when nothing could handle the link.
Future<bool> openInMaps(double latitude, double longitude) async {
  try {
    return await launchUrl(
      mapsUri(latitude, longitude),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// "±40 m" for an accuracy radius, rounded so it does not claim false
/// precision. Null when the platform gave none.
String? accuracyLabel(double? meters) {
  if (meters == null || meters <= 0) return null;
  if (meters >= 1000) return '±${(meters / 1000).toStringAsFixed(1)} km';
  final rounded = meters < 100 ? (meters / 5).round() * 5 : (meters / 10).round() * 10;
  return '±${rounded < 5 ? 5 : rounded} m';
}
