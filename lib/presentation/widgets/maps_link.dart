import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

import 'package:budgett_frontend/core/utils/maps_link.dart';

/// Makes [child] open the coordinates in Google Maps.
///
/// Built on [Link] rather than calling `launchUrl` from a tap handler: on web
/// it renders a real `<a target="_blank">`, which the browser follows as an
/// ordinary link — a scripted `window.open` did nothing there. On Android it
/// still hands the URL to the Maps app.
class MapsLink extends StatelessWidget {
  final double latitude;
  final double longitude;
  final Widget child;
  final BorderRadius? borderRadius;

  const MapsLink({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.child,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) => Link(
        uri: mapsUri(latitude, longitude),
        target: LinkTarget.blank,
        builder: (context, followLink) => InkWell(
          onTap: followLink,
          borderRadius: borderRadius,
          child: child,
        ),
      );
}
