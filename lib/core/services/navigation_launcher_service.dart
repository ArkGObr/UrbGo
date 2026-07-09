import 'dart:io' show Platform;

import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

enum ExternalNavigationApp { googleMaps, waze, appleMaps, browser }

class NavigationLauncherService {
  const NavigationLauncherService();

  String buildGoogleMapsWebUrl({
    required LatLng destination,
    String? waypoint,
    String travelMode = 'driving',
  }) {
    return 'https://www.google.com/maps/dir/?api=1'
        '&destination=${destination.latitude},${destination.longitude}'
        '${waypoint != null ? '&waypoints=$waypoint' : ''}'
        '&travelmode=$travelMode';
  }

  Future<bool> launchNavigation({
    required ExternalNavigationApp app,
    required LatLng destination,
    String? waypoint,
    String travelMode = 'driving',
  }) {
    final googleWebUri = Uri.parse(
      buildGoogleMapsWebUrl(
        destination: destination,
        waypoint: waypoint,
        travelMode: travelMode,
      ),
    );

    final candidateUris = switch (app) {
      ExternalNavigationApp.googleMaps => [
        if (Platform.isAndroid && waypoint == null)
          Uri.parse(
            'google.navigation:q=${destination.latitude},${destination.longitude}'
            '&mode=${travelMode == 'bicycling' ? 'l' : 'd'}',
          ),
        if (Platform.isAndroid)
          Uri.parse(
            'geo:${destination.latitude},${destination.longitude}'
            '?q=${destination.latitude},${destination.longitude}',
          ),
        if (Platform.isIOS)
          Uri.parse(
            'comgooglemaps://?daddr=${destination.latitude},${destination.longitude}'
            '&directionsmode=$travelMode',
          ),
        googleWebUri,
      ],
      ExternalNavigationApp.waze => [
        Uri.parse(
          'waze://?ll=${destination.latitude},${destination.longitude}&navigate=yes',
        ),
        Uri.parse(
          'https://waze.com/ul?ll=${destination.latitude},${destination.longitude}&navigate=yes',
        ),
      ],
      ExternalNavigationApp.appleMaps => [
        Uri.parse(
          'maps://?daddr=${destination.latitude},${destination.longitude}'
          '&dirflg=${travelMode == 'bicycling' ? 'w' : 'd'}',
        ),
        googleWebUri,
      ],
      ExternalNavigationApp.browser => [googleWebUri],
    };

    return launchUriCandidates(candidateUris);
  }

  Future<bool> openExternalUri(Uri uri) => launchUriCandidates([uri]);

  Future<bool> launchUriCandidates(List<Uri> uris) async {
    for (final uri in uris) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  static Uri? extractFirstUri(String text) {
    final match = RegExp(
      r'((?:https?|waze|comgooglemaps|maps):\/\/[^\s]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final raw = match.group(0);
    if (raw == null || raw.isEmpty) return null;

    final sanitized = raw.replaceFirst(RegExp(r'[\)\],.;!?]+$'), '');
    return Uri.tryParse(sanitized);
  }

  static bool isMapUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if ({
      'waze',
      'comgooglemaps',
      'maps',
      'geo',
      'google.navigation',
    }.contains(scheme)) {
      return true;
    }

    if (host.contains('waze.com') || host.contains('maps.app.goo.gl')) {
      return true;
    }

    return host.contains('google.') &&
        (path.contains('/maps') || path.contains('/dir'));
  }
}
