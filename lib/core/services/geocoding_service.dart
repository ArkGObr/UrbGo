import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class GeocodingService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://nominatim.openstreetmap.org',
    headers: {'User-Agent': 'UrbGoApp/1.0'},
  ));

  /// Endereço → coordenadas (forward geocoding)
  Future<LatLng?> geocode(String address) async {
    try {
      final response = await _dio.get('/search', queryParameters: {
        'q': address,
        'format': 'json',
        'limit': 1,
        'countrycodes': 'br',
      });
      final results = response.data as List;
      if (results.isEmpty) return null;
      return LatLng(
        double.parse(results[0]['lat'] as String),
        double.parse(results[0]['lon'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// Coordenadas → endereço (reverse geocoding)
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get('/reverse', queryParameters: {
        'lat': lat,
        'lon': lng,
        'format': 'json',
      });
      return response.data['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }
}
