import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

// ── Modelo de resultado de rota ────────────────────────────────

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationSeconds,
  });

  String get formattedDuration {
    if (durationSeconds < 60) return '< 1 min';
    final mins = (durationSeconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final remainMins = mins % 60;
    return remainMins == 0 ? '${hours}h' : '${hours}h ${remainMins}min';
  }

  String get formattedDistance {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }
}

// ── Serviço de rota com API externa OSRM ────────────────────────
//
// O Google Maps segue sendo usado "por trás" na navegação real via URL/WebView.
// Aqui o app traça a rota para o mapa interno e usa uma estimativa local como fallback.

class RouteService {
  final Dio _dio = Dio();

  /// Retorna a rota real da API OSRM, ou estimativa local se falhar.
  Future<RouteResult> getRouteWithInfo(LatLng from, LatLng to) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};'
          '${to.longitude},${to.latitude}?geometries=geojson&overview=full';

      final response = await _dio.get(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final route = data['routes'][0];

          final distanceMeters = (route['distance'] as num).toDouble();
          final durationSecs = (route['duration'] as num).toInt();

          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List<dynamic>;

          final points = coordinates.map((coord) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          debugPrint(
            '[RouteService] Rota do OSRM carregada com sucesso: ${(distanceMeters / 1000).toStringAsFixed(2)} km',
          );

          return RouteResult(
            points: points,
            distanceKm: distanceMeters / 1000.0,
            durationSeconds: durationSecs,
          );
        }
      }
    } catch (e) {
      debugPrint(
        '[RouteService] Erro no OSRM: $e - caindo para estimativa local',
      );
    }

    return _estimateRoute(from, to);
  }

  /// Wrapper que retorna apenas os pontos (compatibilidade com código existente).
  Future<List<LatLng>> getRoute(LatLng from, LatLng to) async {
    final result = await getRouteWithInfo(from, to);
    return result.points;
  }

  /// Calcula uma rota com múltiplos pontos, concatenando os trechos.
  Future<RouteResult> getRouteWithStops(List<LatLng> stops) async {
    if (stops.isEmpty) {
      return const RouteResult(points: [], distanceKm: 0, durationSeconds: 0);
    }
    if (stops.length == 1) {
      return RouteResult(
        points: [stops.first],
        distanceKm: 0,
        durationSeconds: 0,
      );
    }

    final combinedPoints = <LatLng>[];
    var totalDistanceKm = 0.0;
    var totalDurationSeconds = 0;

    for (var i = 0; i < stops.length - 1; i++) {
      final segment = await getRouteWithInfo(stops[i], stops[i + 1]);
      totalDistanceKm += segment.distanceKm;
      totalDurationSeconds += segment.durationSeconds;

      if (combinedPoints.isEmpty) {
        combinedPoints.addAll(segment.points);
      } else if (segment.points.isNotEmpty) {
        combinedPoints.addAll(segment.points.skip(1));
      }
    }

    return RouteResult(
      points: combinedPoints,
      distanceKm: totalDistanceKm,
      durationSeconds: totalDurationSeconds,
    );
  }

  RouteResult _estimateRoute(LatLng from, LatLng to) {
    final straightKm = _haversineKm(from, to);
    // Mantém uma margem conservadora para percurso urbano real.
    final estimatedKm = straightKm * 1.4;
    // Velocidade média urbana de moto.
    final durationSecs = (estimatedKm / 35.0 * 3600).round();

    debugPrint(
      '[RouteService] Usando estimativa local: '
      '${estimatedKm.toStringAsFixed(2)} km',
    );

    return RouteResult(
      points: [from, to],
      distanceKm: estimatedKm,
      durationSeconds: durationSecs,
    );
  }

  double _haversineKm(LatLng a, LatLng b) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, a, b);
  }
}

// ── Provider ───────────────────────────────────────────────────

final routeServiceProvider = Provider<RouteService>((ref) => RouteService());
