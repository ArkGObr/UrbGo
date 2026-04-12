import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../constants/app_constants.dart';

// ─────────────────────────────────────────────────────────────
// Modelo de sugestão de endereço
// ─────────────────────────────────────────────────────────────

class AddressSuggestion {
  final String label;
  final LatLng coordinates;

  const AddressSuggestion({required this.label, required this.coordinates});
}

// ─────────────────────────────────────────────────────────────
// GeocodingService
// Estratégia: ORS Pelias (primário) → Nominatim (fallback)
//
// ORS Pelias tem cobertura de endereços brasileiros muito melhor
// que o Nominatim puro, e suporta autocomplete.
// ─────────────────────────────────────────────────────────────

class GeocodingService {
  static const _timeout = Duration(seconds: 8);
  static const MethodChannel _channel = MethodChannel('com.urbgo.app/geocoder');

  late final Dio _ors;
  late final Dio _nominatim;

  GeocodingService() {
    _ors = Dio(BaseOptions(
      baseUrl: 'https://api.openrouteservice.org',
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
    ));

    _nominatim = Dio(BaseOptions(
      baseUrl: 'https://nominatim.openstreetmap.org',
      headers: {'User-Agent': 'UrbGoApp/1.0 (urbgo@app.br)'},
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
    ));
  }

  // ──────────────────────────────────────────────────────────
  // Autocomplete — retorna sugestões conforme o usuário digita
  // ──────────────────────────────────────────────────────────

  String _expandAbbreviations(String q) {
    if (q.isEmpty) return q;
    var result = q;
    result = result.replaceAll(RegExp(r'\b(Av|av)\b\.?'), 'Avenida');
    result = result.replaceAll(RegExp(r'\b(R|r)\b\.?(?![\w])'), 'Rua');
    result = result.replaceAll(RegExp(r'\b(Dr|dr)\b\.?'), 'Doutor');
    result = result.replaceAll(RegExp(r'\b(Prof|prof)\b\.?'), 'Professor');
    result = result.replaceAll(RegExp(r'\b(Pca|pca)\b\.?', caseSensitive: false), 'Praça');
    result = result.replaceAll(RegExp(r'\b(Praca|praca)\b\.?', caseSensitive: false), 'Praça');
    return result;
  }

  /// [focusPoint] é a posição atual do usuário — quando fornecido,
  /// os resultados são ordenados por proximidade a esse ponto.
  Future<List<AddressSuggestion>> autocomplete(
    String query, {
    LatLng? focusPoint,
  }) async {
    final q = _expandAbbreviations(query.trim());
    if (q.length < 3) return [];

    // 1. Nativo (Google Maps via Android Geocoder sem API key)
    try {
      final results = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'geocode',
        {
          'query': q,
          'focusLat': focusPoint?.latitude,
          'focusLng': focusPoint?.longitude,
        },
      );
      if (results != null && results.isNotEmpty) {
        return results.map((m) {
          return AddressSuggestion(
            label: m['label'] as String,
            coordinates: LatLng(m['lat'] as double, m['lng'] as double),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('[GeocodingService] Native geocoder fallback (autocomplete): $e');
    }

    // 2. ORS Pelias autocomplete (com bias de localização)
    final ors = await _orsAutocomplete(q, focusPoint: focusPoint);
    if (ors.isNotEmpty) return ors;

    // 3. Fallback: Nominatim search
    return _nominatimSearch(q, limit: 5, focusPoint: focusPoint);
  }

  Future<List<AddressSuggestion>> _orsAutocomplete(
    String query, {
    LatLng? focusPoint,
  }) async {
    try {
      final apiKey = AppConstants.orsApiKey;
      if (apiKey.isEmpty) return [];

      final params = <String, dynamic>{
        'api_key': apiKey,
        'text': query,
        'boundary.country': 'BRA',
        'lang': 'pt',
        'size': 6,
        'layers': 'address,street,venue,locality',
      };

      // Bias de localização: resultados próximos ao usuário sobem no ranking
      if (focusPoint != null) {
        params['focus.point.lat'] = focusPoint.latitude;
        params['focus.point.lon'] = focusPoint.longitude;
        // Restrito a um raio geográfico aproximado (~50km)
        params['boundary.rect.min_lon'] = focusPoint.longitude - 0.5;
        params['boundary.rect.min_lat'] = focusPoint.latitude - 0.5;
        params['boundary.rect.max_lon'] = focusPoint.longitude + 0.5;
        params['boundary.rect.max_lat'] = focusPoint.latitude + 0.5;
      }

      final response = await _ors.get(
        '/geocode/autocomplete',
        queryParameters: params,
      );

      final features = (response.data['features'] as List?) ?? [];
      return features
          .where((f) => f['geometry']?['coordinates'] != null)
          .map<AddressSuggestion>((f) {
            final coords = f['geometry']['coordinates'] as List;
            final props = (f['properties'] as Map<String, dynamic>?) ?? {};
            final label = (props['label'] as String?)?.trim() ??
                (props['name'] as String?)?.trim() ??
                query;
            return AddressSuggestion(
              label: label,
              coordinates: LatLng(
                (coords[1] as num).toDouble(),
                (coords[0] as num).toDouble(),
              ),
            );
          })
          .where((s) => s.label.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[GeocodingService] ORS autocomplete error: $e');
      return [];
    }
  }

  Future<List<AddressSuggestion>> _nominatimSearch(
    String query, {
    int limit = 5,
    LatLng? focusPoint,
  }) async {
    try {
      final params = <String, dynamic>{
        'q': query,
        'format': 'json',
        'limit': limit,
        'countrycodes': 'br',
        'addressdetails': 1,
        'accept-language': 'pt-BR',
      };

      // Soft bias: ponto de referência para ordenação por proximidade
      if (focusPoint != null) {
        params['lat'] = focusPoint.latitude;
        params['lon'] = focusPoint.longitude;
        params['viewbox'] = '${focusPoint.longitude - 0.5},${focusPoint.latitude + 0.5},${focusPoint.longitude + 0.5},${focusPoint.latitude - 0.5}';
        params['bounded'] = 1;
      }

      final response = await _nominatim.get('/search', queryParameters: params);

      final results = (response.data as List?) ?? [];
      return results.map<AddressSuggestion>((r) {
        return AddressSuggestion(
          label: _buildNominatimLabel(r),
          coordinates: LatLng(
            double.parse(r['lat'] as String),
            double.parse(r['lon'] as String),
          ),
        );
      }).toList();
    } catch (e) {
      debugPrint('[GeocodingService] Nominatim search error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────
  // Forward geocoding — endereço → coordenadas
  // ──────────────────────────────────────────────────────────

  Future<LatLng?> geocode(String address) async {
    final q = address.trim();
    if (q.isEmpty) return null;

    // 1. Nativo (Google Maps)
    try {
      final results = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'geocode',
        {'query': q},
      );
      if (results != null && results.isNotEmpty) {
        return LatLng(
          results[0]['lat'] as double,
          results[0]['lng'] as double,
        );
      }
    } catch (e) {
      debugPrint('[GeocodingService] Native geocoder fallback (geocode): $e');
    }

    // 2. ORS Pelias search
    final orsResult = await _orsGeocode(q);
    if (orsResult != null) return orsResult;

    // 3. Fallback Nominatim
    return _nominatimGeocode(q);
  }

  Future<LatLng?> _orsGeocode(String address) async {
    try {
      final apiKey = AppConstants.orsApiKey;
      if (apiKey.isEmpty) return null;

      final response = await _ors.get(
        '/geocode/search',
        queryParameters: {
          'api_key': apiKey,
          'text': address,
          'boundary.country': 'BRA',
          'lang': 'pt',
          'size': 1,
        },
      );

      final features = (response.data['features'] as List?) ?? [];
      if (features.isEmpty) return null;
      final coords = features[0]['geometry']['coordinates'] as List;
      return LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      );
    } catch (e) {
      debugPrint('[GeocodingService] ORS geocode error: $e');
      return null;
    }
  }

  Future<LatLng?> _nominatimGeocode(String address) async {
    try {
      final response = await _nominatim.get('/search', queryParameters: {
        'q': address,
        'format': 'json',
        'limit': 1,
        'countrycodes': 'br',
        'accept-language': 'pt-BR',
      });

      final results = (response.data as List?) ?? [];
      if (results.isEmpty) return null;
      return LatLng(
        double.parse(results[0]['lat'] as String),
        double.parse(results[0]['lon'] as String),
      );
    } catch (e) {
      debugPrint('[GeocodingService] Nominatim geocode error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Reverse geocoding — coordenadas → endereço legível
  // ──────────────────────────────────────────────────────────

  Future<String?> reverseGeocode(double lat, double lng) async {
    // 1. Nativo (Google Maps)
    try {
      final result = await _channel.invokeMethod<String>(
        'reverseGeocode',
        {'lat': lat, 'lng': lng},
      );
      if (result != null && result.isNotEmpty) return result;
    } catch (e) {
      debugPrint('[GeocodingService] Native geocoder fallback (reverse): $e');
    }

    // 2. ORS reverse
    final orsResult = await _orsReverse(lat, lng);
    if (orsResult != null) return orsResult;

    // 3. Fallback Nominatim
    return _nominatimReverse(lat, lng);
  }

  Future<String?> _orsReverse(double lat, double lng) async {
    try {
      final apiKey = AppConstants.orsApiKey;
      if (apiKey.isEmpty) return null;

      final response = await _ors.get(
        '/geocode/reverse',
        queryParameters: {
          'api_key': apiKey,
          'point.lat': lat,
          'point.lon': lng,
          'lang': 'pt',
          'size': 1,
          'layers': 'address,street',
        },
      );

      final features = (response.data['features'] as List?) ?? [];
      if (features.isEmpty) return null;
      return features[0]['properties']['label'] as String?;
    } catch (e) {
      debugPrint('[GeocodingService] ORS reverse error: $e');
      return null;
    }
  }

  Future<String?> _nominatimReverse(double lat, double lng) async {
    try {
      final response = await _nominatim.get('/reverse', queryParameters: {
        'lat': lat,
        'lon': lng,
        'format': 'json',
        'accept-language': 'pt-BR',
      });
      return response.data['display_name'] as String?;
    } catch (e) {
      debugPrint('[GeocodingService] Nominatim reverse error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────

  /// Constrói um label limpo a partir dos detalhes de endereço do Nominatim.
  String _buildNominatimLabel(Map<String, dynamic> result) {
    final addr = (result['address'] as Map<String, dynamic>?) ?? {};
    final parts = <String>[];

    final road = addr['road'] as String?;
    final num = addr['house_number'] as String?;
    if (road != null) {
      parts.add(num != null ? '$road, $num' : road);
    }

    final suburb = addr['suburb'] ?? addr['neighbourhood'];
    if (suburb != null) parts.add(suburb as String);

    final city = addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['village'];
    if (city != null) parts.add(city as String);

    final state = addr['state'] as String?;
    if (state != null) {
      // Abreviação do estado
      final stateCode = _brStateCode(state);
      parts.add(stateCode ?? state);
    }

    return parts.isNotEmpty
        ? parts.join(', ')
        : (result['display_name'] as String? ?? '');
  }

  static const _stateMap = {
    'Acre': 'AC', 'Alagoas': 'AL', 'Amapá': 'AP', 'Amazonas': 'AM',
    'Bahia': 'BA', 'Ceará': 'CE', 'Distrito Federal': 'DF',
    'Espírito Santo': 'ES', 'Goiás': 'GO', 'Maranhão': 'MA',
    'Mato Grosso': 'MT', 'Mato Grosso do Sul': 'MS', 'Minas Gerais': 'MG',
    'Pará': 'PA', 'Paraíba': 'PB', 'Paraná': 'PR', 'Pernambuco': 'PE',
    'Piauí': 'PI', 'Rio de Janeiro': 'RJ', 'Rio Grande do Norte': 'RN',
    'Rio Grande do Sul': 'RS', 'Rondônia': 'RO', 'Roraima': 'RR',
    'Santa Catarina': 'SC', 'São Paulo': 'SP', 'Sergipe': 'SE',
    'Tocantins': 'TO',
  };

  String? _brStateCode(String state) => _stateMap[state];
}
