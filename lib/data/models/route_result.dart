import 'package:latlong2/latlong.dart';

enum RouteSource { osrm, google, osrmFallback }

class RouteResult {
  final double distanceMeters;
  final int durationSeconds;
  final int durationInTrafficSeconds;
  final RouteSource source;
  final List<LatLng> polyline;
  final double trafficRatio;
  final double tollCostBrl;
  final DateTime computedAt;

  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.durationInTrafficSeconds,
    required this.source,
    required this.polyline,
    required this.trafficRatio,
    this.tollCostBrl = 0,
    required this.computedAt,
  });

  double get distanceKm => distanceMeters / 1000;

  bool get isFallback => source == RouteSource.osrmFallback;

  String get sourceLabel => switch (source) {
    RouteSource.osrm => 'osrm',
    RouteSource.google => 'google',
    RouteSource.osrmFallback => 'osrm_fallback',
  };

  String get trafficConditionLabel {
    if (trafficRatio > 1.35) return 'PESADO';
    if (trafficRatio >= 1.15) return 'MODERADO';
    return 'LIVRE';
  }

  Map<String, dynamic> toJson() => {
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'durationInTrafficSeconds': durationInTrafficSeconds,
    'source': sourceLabel,
    'polyline': [
      for (final point in polyline) [point.latitude, point.longitude],
    ],
    'trafficRatio': trafficRatio,
    'tollCostBrl': tollCostBrl,
    'computedAt': computedAt.toIso8601String(),
  };

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final rawPolyline = json['polyline'] as List<dynamic>? ?? const [];
    return RouteResult(
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationSeconds: (json['durationSeconds'] as num).round(),
      durationInTrafficSeconds:
          (json['durationInTrafficSeconds'] as num?)?.round() ??
          (json['durationSeconds'] as num).round(),
      source: switch (json['source']) {
        'google' => RouteSource.google,
        'osrm_fallback' => RouteSource.osrmFallback,
        _ => RouteSource.osrm,
      },
      polyline: [
        for (final point in rawPolyline)
          LatLng(
            ((point as List<dynamic>)[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ),
      ],
      trafficRatio: (json['trafficRatio'] as num?)?.toDouble() ?? 1,
      tollCostBrl: (json['tollCostBrl'] as num?)?.toDouble() ?? 0,
      computedAt: json['computedAt'] != null
          ? DateTime.parse(json['computedAt'] as String)
          : DateTime.now(),
    );
  }
}
