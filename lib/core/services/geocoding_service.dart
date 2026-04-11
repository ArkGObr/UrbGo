import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

  /// [focusPoint] é a posição atual do usuário — quando fornecido,
  /// os resultados são ordenados por proximidade a esse ponto.
  Future<List<AddressSuggestion>> autocomplete(
    String query, {
    LatLng? focusPoint,
  }) async {
    final q = query.trim();
    if (q.length < 3) return [];

    // 1. ORS Pelias autocomplete (com bias de localização)
    final ors = await _orsAutocomplete(q, focusPoint: focusPoint);
    if (ors.isNotEmpty) return ors;

    // 2. Fallback: Nominatim search
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

    // 1. ORS Pelias search
    final orsResult = await _orsGeocode(q);
    if (orsResult != null) return orsResult;

    // 2. Fallback Nominatim
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
    // 1. ORS reverse
    final orsResult = await _orsReverse(lat, lng);
    if (orsResult != null) return orsResult;

    // 2. Fallback Nominatim
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
