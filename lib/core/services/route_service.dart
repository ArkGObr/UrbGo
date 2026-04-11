import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../constants/app_constants.dart';

class RouteService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.orsBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 12),
  ));

  /// Retorna os pontos da rota entre dois pontos via estradas reais.
  /// Usa OpenRouteService (plano gratuito: 2.000 req/dia).
  /// Fallback: linha reta se a API falhar.
  Future<List<LatLng>> getRoute(LatLng from, LatLng to) async {
    final apiKey = AppConstants.orsApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[RouteService] ORS API key não configurada — usando linha reta');
      return [from, to];
    }

    try {
      final response = await _dio.get(
        '/v2/directions/driving-car',
        queryParameters: {
          'api_key': apiKey,
          'start': '${from.longitude},${from.latitude}',
          'end': '${to.longitude},${to.latitude}',
        },
      );

      final features = response.data['features'] as List?;
      if (features == null || features.isEmpty) {
        debugPrint('[RouteService] ORS retornou sem features — usando linha reta');
        return [from, to];
      }

      final coords =
          features[0]['geometry']['coordinates'] as List;

      if (coords.isEmpty) return [from, to];

      return coords
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
    } on DioException catch (e) {
      debugPrint('[RouteService] Erro ORS (${e.response?.statusCode}): ${e.message}');
      if (e.response?.statusCode == 403) {
        debugPrint('[RouteService] API key inválida ou limite excedido');
      }
      return [from, to];
    } catch (e) {
      debugPrint('[RouteService] Erro inesperado: $e');
      return [from, to];
    }
  }
}
