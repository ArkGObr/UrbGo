import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

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
// Usa somente o geocoder nativo do dispositivo.
// No Android isso aproveita o Google Maps/serviços do sistema sem API key.
// ─────────────────────────────────────────────────────────────

class GeocodingService {
  static const MethodChannel _channel = MethodChannel('com.arkgo.app/geocoder');

  String _expandAbbreviations(String q) {
    if (q.isEmpty) return q;
    var result = q;
    result = result.replaceAll(RegExp(r'\b(Av|av)\b\.?'), 'Avenida');
    result = result.replaceAll(RegExp(r'\b(R|r)\b\.?(?![\w])'), 'Rua');
    result = result.replaceAll(RegExp(r'\b(Dr|dr)\b\.?'), 'Doutor');
    result = result.replaceAll(RegExp(r'\b(Prof|prof)\b\.?'), 'Professor');
    result = result.replaceAll(
      RegExp(r'\b(Pca|pca)\b\.?', caseSensitive: false),
      'Praça',
    );
    result = result.replaceAll(
      RegExp(r'\b(Praca|praca)\b\.?', caseSensitive: false),
      'Praça',
    );
    return result;
  }

  Future<List<AddressSuggestion>> autocomplete(
    String query, {
    LatLng? focusPoint,
  }) async {
    final q = _expandAbbreviations(query.trim());
    if (q.length < 3) return [];

    try {
      final results = await _channel
          .invokeListMethod<Map<dynamic, dynamic>>('geocode', {
            'query': q,
            'focusLat': focusPoint?.latitude,
            'focusLng': focusPoint?.longitude,
          });

      if (results == null || results.isEmpty) return [];

      return results.map((m) {
        return AddressSuggestion(
          label: m['label'] as String,
          coordinates: LatLng(m['lat'] as double, m['lng'] as double),
        );
      }).toList();
    } catch (e) {
      debugPrint('[GeocodingService] Native geocoder error (autocomplete): $e');
      return [];
    }
  }

  Future<LatLng?> geocode(String address) async {
    final q = address.trim();
    if (q.isEmpty) return null;

    try {
      final results = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'geocode',
        {'query': q},
      );
      if (results == null || results.isEmpty) return null;

      return LatLng(results[0]['lat'] as double, results[0]['lng'] as double);
    } catch (e) {
      debugPrint('[GeocodingService] Native geocoder error (geocode): $e');
      return null;
    }
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final result = await _channel.invokeMethod<String>('reverseGeocode', {
        'lat': lat,
        'lng': lng,
      });
      if (result == null || result.isEmpty) return null;
      return result;
    } catch (e) {
      debugPrint('[GeocodingService] Native geocoder error (reverse): $e');
      return null;
    }
  }
}
