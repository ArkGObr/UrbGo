import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../domain/delivery_model.dart';

class DeliveryRepository {
  final SupabaseClient _db = Supabase.instance.client;

  static const _selectWithMotoboy =
      '*, motoboys(vehicle_plate, current_lat, current_lng, avg_rating, total_ratings, users(name, phone))';

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
    required double distanceKm,
    VehicleCategory vehicleCategory = VehicleCategory.motoboy,
    String? extraStopAddress,
    double? extraStopLat,
    double? extraStopLng,
    // Campos por categoria
    String? recipientName,
    String? recipientPhone,
    String? itemDescription,
    bool isFragile = false,
    double? declaredValue,
    int helperCount = 0,
    bool roundTrip = false,
    DateTime? scheduledFor,
    String? cargoType,
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
          'vehicle_category': vehicleCategory.info.id,
          'status': 'pending',
          'distance_km': double.parse(distanceKm.toStringAsFixed(2)),
          if (extraStopAddress != null) 'extra_stop_address': extraStopAddress,
          if (extraStopLat != null) 'extra_stop_lat': extraStopLat,
          if (extraStopLng != null) 'extra_stop_lng': extraStopLng,
          if (recipientName != null) 'recipient_name': recipientName,
          if (recipientPhone != null) 'recipient_phone': recipientPhone,
          if (itemDescription != null && itemDescription.isNotEmpty)
            'item_description': itemDescription,
          if (isFragile) 'is_fragile': true,
          if (declaredValue != null) 'declared_value': declaredValue,
          if (helperCount > 0) 'helper_count': helperCount,
          if (roundTrip) 'is_round_trip': true,
          if (scheduledFor != null) 'scheduled_for': scheduledFor.toIso8601String(),
          if (cargoType != null) 'cargo_type': cargoType,
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

  Future<List<DeliveryModel>> getClientHistoryPage({
    required String clientId,
    required int offset,
    int limit = 20,
  }) async {
    final data = await _db
        .from('deliveries')
        .select(_selectWithMotoboy)
        .eq('client_id', clientId)
        .inFilter('status', ['completed', 'cancelled'])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((e) => DeliveryModel.fromJson(e)).toList();
  }

  /// Cancelar entrega (pendente, ou aceita há menos de 5 min)
  Future<void> cancelDelivery(String deliveryId) async {
    // Tenta cancelar se pendente
    var res = await _db
        .from('deliveries')
        .update({'status': 'cancelled'})
        .eq('id', deliveryId)
        .eq('status', 'pending')
        .select('id');

    if ((res as List).isNotEmpty) return;

    // Tenta cancelar se aceita há menos de 5 min
    final cutoff = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .toIso8601String();
    res = await _db
        .from('deliveries')
        .update({'status': 'cancelled'})
        .eq('id', deliveryId)
        .eq('status', 'accepted')
        .gte('accepted_at', cutoff)
        .select('id');

    if ((res as List).isEmpty) {
      throw Exception(
        'Não é possível cancelar após o entregador já estar a caminho há mais de 5 minutos.',
      );
    }
  }

  /// Upload de foto de confirmação de entrega
  Future<String> uploadDeliveryPhoto(String deliveryId, File imageFile) async {
    final path =
        'deliveries/$deliveryId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage
        .from('delivery-photos')
        .upload(
          path,
          imageFile,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    final url = _db.storage.from('delivery-photos').getPublicUrl(path);
    await _db
        .from('deliveries')
        .update({'delivery_photo_url': url})
        .eq('id', deliveryId);
    return url;
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
