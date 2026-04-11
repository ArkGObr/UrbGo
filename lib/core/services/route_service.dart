import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Resultado de rota contendo pontos, distância e duração
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
    if (remainMins == 0) return '${hours}h';
    return '${hours}h ${remainMins}min';
  }

  String get formattedDistance {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()} m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }
}

class RouteService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Retorna a Rota Real desenhada no mapa e os dados calculados de Distância/Tempo.
  Future<RouteResult> getRouteWithInfo(LatLng from, LatLng to) async {
    try {
      final response = await _dio.get(
        'http://router.project-osrm.org/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        queryParameters: {
          'overview': 'full',
          'geometries': 'geojson',
        },
      );

      final routes = response.data['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final route = routes.first;
        
        // 1. Pega os pontos para desenhar o traçado sinuoso exato da rua
        final coords = route['geometry']?['coordinates'] as List?;
        List<LatLng> points = [];
        if (coords != null) {
          points = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        }

        // 2. Extrai a distância que a API encontrou
        final apiDistanceKm = ((route['distance'] as num?) ?? 0).toDouble() / 1000;
        final apiDurationSecs = ((route['duration'] as num?) ?? 0).round();

        // 3. Trava de Proteção Contra Prejuízo (Profit Protection)
        // Se a API retornar uma distância absurdamente curta por desatualização, 
        // nós assumimos um mínimo seguro baseado na linha reta (+ 30% de margem urbana).
        final straightKm = _haversineKm(from, to);
        final safeMinimumKm = straightKm * 1.30;
        
        final finalDistanceKm = max(apiDistanceKm, safeMinimumKm);
        
        final finalDurationSecs = apiDurationSecs > 0 
            ? apiDurationSecs 
            // 40km/h media de moto na área metropolitana pra recalcular o safeTime
            : (finalDistanceKm / 40.0 * 3600).round();

        // Volta com os pontos para a linha azul perfeira da curva e o Valor Protegido.
        return RouteResult(
          points: points.isNotEmpty ? points : [from, to],
          distanceKm: finalDistanceKm,
          durationSeconds: finalDurationSecs,
        );
      }
    } catch (e) {
      debugPrint('[RouteService] OSRM public API fetch error: $e');
    }

    // Fallback absoluto: desenha linha reta pontilhada / sem polylines
    return _fallback(from, to);
  }

  /// Mantém compatibilidade — retorna só os pontos
  Future<List<LatLng>> getRoute(LatLng from, LatLng to) async {
    final result = await getRouteWithInfo(from, to);
    return result.points;
  }

  RouteResult _fallback(LatLng from, LatLng to) {
    final straightDist = _haversineKm(from, to);
    final estimatedRealDistance = straightDist * 1.4; 
    final duration = (estimatedRealDistance / 35.0 * 3600).round(); 

    return RouteResult(
      points: [from, to],
      distanceKm: estimatedRealDistance,
      durationSeconds: duration,
    );
  }

  double _haversineKm(LatLng a, LatLng b) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, a, b);
  }
}
