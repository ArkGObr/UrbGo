import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../client/domain/delivery_model.dart';
import '../domain/motoboy_model.dart';

class MotoboyRepository {
  final SupabaseClient _db = Supabase.instance.client;
  Timer? _locationTimer;

  /// Buscar dados do motoboy logado (com join na tabela users)
  Future<MotoboyModel> fetchMotoboy(String id) async {
    final data = await _db
        .from('motoboys')
        .select('*, users(name, phone)')
        .eq('id', id)
        .single();
    return MotoboyModel.fromJson(data);
  }

  /// Stream do motoboy em tempo real (saldo, online status, etc.)
  Stream<MotoboyModel> watchMotoboy(String id) {
    return _db
        .from('motoboys')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => MotoboyModel.fromJson(rows.first));
  }

  /// Ligar/desligar online
  Future<void> setOnline(String id, bool online) async {
    await _db.from('motoboys').update({
      'is_online': online,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Buscar corridas disponíveis por raio, filtradas pela categoria do motoboy
  Future<List<DeliveryModel>> getAvailableRuns({
    required String motoboyId,
    required double lat,
    required double lng,
    double radiusKm = 10.0,
  }) async {
    // Buscar categoria do motoboy (com fallback se RLS falhar)
    String category = 'motoboy';
    try {
      final m = await _db
          .from('motoboys')
          .select('vehicle_category')
          .eq('id', motoboyId)
          .single();
      category = m['vehicle_category'] as String? ?? 'motoboy';
    } catch (_) {
      // Se falhar (ex: recursão RLS), segue com default
    }

    // Buscar corridas pendentes
    // Tenta filtrar por categoria; se não houver resultados, busca todas
    var data = await _db
        .from('deliveries')
        .select()
        .eq('status', 'pending')
        .eq('vehicle_category', category)
        .order('created_at', ascending: false)
        .limit(50);

    // Se não encontrou pela categoria, tenta sem filtro de categoria
    if ((data as List).isEmpty) {
      data = await _db
          .from('deliveries')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(50);
    }

    final all =
        (data as List).map((e) => DeliveryModel.fromJson(e)).toList();

    // Filtrar por raio no cliente (Haversine)
    return all.where((d) {
      final dist = _haversineDistanceKm(
        lat, lng, d.pickupLat, d.pickupLng,
      );
      return dist <= radiusKm;
    }).toList();
  }

  /// Stream de novas corridas disponíveis (Realtime)
  RealtimeChannel watchAvailableRuns(void Function() onNewRun) {
    return _db
        .channel('available-runs')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'deliveries',
          callback: (_) => onNewRun(),
        )
        .subscribe();
  }

  /// Buscar histórico de corridas finalizadas ou canceladas pelo motoboy
  Future<List<DeliveryModel>> getRunHistory(String motoboyId) async {
    final data = await _db
        .from('deliveries')
        .select('*, motoboys(vehicle_plate, current_lat, current_lng, users(name, phone))')
        .eq('motoboy_id', motoboyId)
        .inFilter('status', ['completed', 'cancelled'])
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List).map((e) => DeliveryModel.fromJson(e)).toList();
  }

  // ── ACEITAR CORRIDA ──────────────────────────────────────
  /// Valida saldo ANTES de aceitar
  Future<void> acceptDelivery({
    required String deliveryId,
    required String motoboyId,
    required double commission,
  }) async {
    // 1. Busca saldo atual
    final m = await _db
        .from('motoboys')
        .select('wallet_balance')
        .eq('id', motoboyId)
        .single();
    final balance = (m['wallet_balance'] as num).toDouble();

    if (balance < commission) {
      throw InsufficientBalanceException(
        'Saldo insuficiente. Você tem ${CurrencyFormatter.format(balance)}'
        ' mas precisa de ${CurrencyFormatter.format(commission)}.',
      );
    }

    // 2. Verifica se a corrida ainda está pendente
    final delivery = await _db
        .from('deliveries')
        .select('status, motoboy_id')
        .eq('id', deliveryId)
        .maybeSingle();

    if (delivery == null) {
      throw Exception('Corrida não encontrada.');
    }

    if (delivery['status'] != 'pending') {
      throw Exception('Esta corrida já foi aceita por outro entregador.');
    }

    // 3. Aceita a corrida (atualiza status e motoboy_id)
    final updated = await _db
        .from('deliveries')
        .update({
          'motoboy_id': motoboyId,
          'status': 'accepted',
          'accepted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', deliveryId)
        .select('status, motoboy_id');

    // 4. Verifica se o update realmente aconteceu
    if ((updated as List).isEmpty) {
      throw Exception(
        'Não foi possível aceitar a corrida. '
        'Verifique suas permissões ou tente novamente.',
      );
    }

    final afterStatus = updated.first['status'];
    if (afterStatus != 'accepted') {
      throw Exception(
        'Falha ao aceitar corrida (status: $afterStatus). Tente novamente.',
      );
    }
  }

  /// Confirmar coleta (accepted → in_progress)
  Future<void> confirmPickup(String deliveryId) async {
    await _db
        .from('deliveries')
        .update({'status': 'in_progress'})
        .eq('id', deliveryId);
  }

  /// Finalizar entrega → trigger SQL desconta 25%
  Future<void> completeDelivery(String deliveryId) async {
    await _db
        .from('deliveries')
        .update({
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', deliveryId);
  }

  // ── GPS ──────────────────────────────────────────────────
  void startLocationUpdates(String motoboyId) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      const Duration(seconds: AppConstants.locationUpdateIntervalSeconds),
      (_) async {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          await _db.from('motoboys').update({
            'current_lat': pos.latitude,
            'current_lng': pos.longitude,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', motoboyId);
        } catch (_) {
          /* ignora erros de GPS */
        }
      },
    );
  }

  void stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  // ── Haversine ────────────────────────────────────────────
  double _haversineDistanceKm(
    double lat1, double lng1, double lat2, double lng2,
  ) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lng2 - lng1);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * asin(sqrt(h));
  }

  double _toRad(double deg) => deg * pi / 180;
}

class InsufficientBalanceException implements Exception {
  final String message;
  InsufficientBalanceException(this.message);
  @override
  String toString() => message;
}
