import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';

class RouteService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.orsBaseUrl,
  ));

  /// Retorna lista de pontos da rota entre dois pontos
  /// Usa OpenRouteService (plano gratuito: 2.000 req/dia)
  Future<List<LatLng>> getRoute(LatLng from, LatLng to) async {
    try {
      final response = await _dio.get(
        '/v2/directions/driving-car',
        queryParameters: {
          'api_key': AppConstants.orsApiKey,
          'start': '${from.longitude},${from.latitude}',
          'end': '${to.longitude},${to.latitude}',
        },
      );
      final coords =
          response.data['features'][0]['geometry']['coordinates'] as List;
      return coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
    } catch (_) {
      // Fallback: linha reta se ORS falhar
      return [from, to];
    }
  }
}
