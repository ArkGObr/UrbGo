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
    final res = await _db
        .from('delivery_ratings')
        .select('id')
        .eq('delivery_id', deliveryId)
        .maybeSingle();
    return res != null;
  }
}
