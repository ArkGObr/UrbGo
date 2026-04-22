import 'package:supabase_flutter/supabase_flutter.dart';

class RatingRepository {
  final _db = Supabase.instance.client;

  Future<void> submitRating({
    required String deliveryId,
    required String clientId,
    required String motoboyId,
    required int rating,
    String? comment,
  }) async {
    await _db.from('delivery_ratings').insert({
      'delivery_id': deliveryId,
      'client_id': clientId,
      'motoboy_id': motoboyId,
      'rating': rating,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
    });
  }

  Future<bool> hasRated(String deliveryId) async {
    try {
      final res = await _db
          .from('delivery_ratings')
          .select('id')
          .eq('delivery_id', deliveryId)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  /// Retorna mapa deliveryId → nota (1-5) de todas as avaliações do cliente.
  Future<Map<String, int>> getClientRatings(String clientId) async {
    try {
      final res = await _db
          .from('delivery_ratings')
          .select('delivery_id, rating')
          .eq('client_id', clientId);
      return Map.fromEntries(
        (res as List).map(
          (r) => MapEntry(r['delivery_id'] as String, r['rating'] as int),
        ),
      );
    } catch (_) {
      return {};
    }
  }
}
