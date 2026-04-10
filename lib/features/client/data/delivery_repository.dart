import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/delivery_model.dart';

class DeliveryRepository {
  final SupabaseClient _db = Supabase.instance.client;

  static const _selectWithMotoboy =
      '*, motoboys(vehicle_plate, current_lat, current_lng, users(name, phone))';

  /// Criar entrega
  Future<DeliveryModel> createDelivery({
    required String clientId,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
    required double value,
    required String paymentMethod,
  }) async {
    final commission = value * 0.25;
    final data = await _db
        .from('deliveries')
        .insert({
          'client_id': clientId,
          'pickup_address': pickupAddress,
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'delivery_address': deliveryAddress,
          'delivery_lat': deliveryLat,
          'delivery_lng': deliveryLng,
          'value': value,
          'commission': commission,
          'payment_method': paymentMethod,
          'status': 'pending',
        })
        .select(_selectWithMotoboy)
        .single();
    return DeliveryModel.fromJson(data);
  }

  /// Listar entregas do cliente (ordenadas por data mais recente)
  Future<List<DeliveryModel>> getClientDeliveries(String clientId) async {
    final data = await _db
        .from('deliveries')
        .select(_selectWithMotoboy)
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => DeliveryModel.fromJson(e)).toList();
  }

  /// Cancelar entrega (apenas status pending)
  Future<void> cancelDelivery(String deliveryId) async {
    await _db
        .from('deliveries')
        .update({'status': 'cancelled'})
        .eq('id', deliveryId)
        .eq('status', 'pending');
  }

  /// Buscar uma entrega específica
  Future<DeliveryModel> getDelivery(String deliveryId) async {
    final data = await _db
        .from('deliveries')
        .select(_selectWithMotoboy)
        .eq('id', deliveryId)
        .single();
    return DeliveryModel.fromJson(data);
  }

  /// Stream em tempo real de uma entrega específica
  Stream<DeliveryModel> watchDelivery(String deliveryId) {
    return _db
        .from('deliveries')
        .stream(primaryKey: ['id'])
        .eq('id', deliveryId)
        .map((rows) => DeliveryModel.fromJson(rows.first));
  }

  /// Stream em tempo real da posição do motoboy
  RealtimeChannel watchMotoboyLocation({
    required String motoboyId,
    required void Function(double lat, double lng) onUpdate,
  }) {
    return _db
        .channel('motoboy-$motoboyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'motoboys',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: motoboyId,
          ),
          callback: (payload) {
            final lat = payload.newRecord['current_lat'] as double?;
            final lng = payload.newRecord['current_lng'] as double?;
            if (lat != null && lng != null) onUpdate(lat, lng);
          },
        )
        .subscribe();
  }
}
