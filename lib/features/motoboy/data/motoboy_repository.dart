import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../client/domain/delivery_model.dart';
import '../domain/driver_registration_rules.dart';
import '../domain/earnings_dashboard.dart';
import '../domain/motoboy_model.dart';

class MotoboyRepository {
  final SupabaseClient _db = Supabase.instance.client;
  Timer? _locationTimer;

  /// Buscar dados do motoboy logado (com join na tabela users)
  Future<MotoboyModel> fetchMotoboy(String id) async {
    final data = await _db
        .from('motoboys')
        .select('*, users(name, phone, status, is_released)')
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
        .asyncMap((_) => fetchMotoboy(id));
  }

  /// Ligar/desligar online (ao ligar, registra last_active_at e reseta nível de inatividade via trigger SQL)
  Future<void> setOnline(String id, bool online) async {
    if (online) {
      final motoboy = await fetchMotoboy(id);
      _ensureApproved(motoboy);
    }

    final now = DateTime.now().toIso8601String();
    await _db
        .from('motoboys')
        .update({
          'is_online': online,
          'updated_at': now,
          if (online) 'last_active_at': now,
        })
        .eq('id', id);
  }

  /// Buscar corridas disponíveis por raio, filtradas pela categoria do motoboy
  Future<List<DeliveryModel>> getAvailableRuns({
    required String motoboyId,
    required double lat,
    required double lng,
    double radiusKm = 10.0,
  }) async {
    final context = await _loadAvailabilityContext(motoboyId);
    final category = context.category;
    final isApproved = context.isApproved;

    if (!isApproved) return [];

    final all = await _loadQueuedAvailableRuns(
      motoboyId: motoboyId,
      fallbackCategory: category,
    );

    // Filtrar por raio no cliente (Haversine)
    return all.where((d) {
      final dist = _haversineDistanceKm(lat, lng, d.pickupLat, d.pickupLng);
      return dist <= radiusKm;
    }).toList();
  }

  Future<({String category, bool isApproved})> _loadAvailabilityContext(
    String motoboyId,
  ) async {
    try {
      final motoboyRow = await _db
          .from('motoboys')
          .select('vehicle_category, approval_status')
          .eq('id', motoboyId)
          .maybeSingle();
      final userRow = await _db
          .from('users')
          .select('status, is_released')
          .eq('id', motoboyId)
          .maybeSingle();

      final category = motoboyRow?['vehicle_category'] as String? ?? 'motoboy';
      final approvalStatus = motoboyRow?['approval_status'] as String?;
      final isReleased = userRow?['is_released'] == true;
      final isActive = userRow?['status'] == 'active';

      final isApproved =
          approvalStatus == 'approved' || (isReleased && isActive);

      return (category: category, isApproved: isApproved);
    } catch (_) {
      return (category: 'motoboy', isApproved: false);
    }
  }

  Future<List<DeliveryModel>> _loadQueuedAvailableRuns({
    required String motoboyId,
    required String fallbackCategory,
  }) async {
    final driverCategory = VehicleCategoryExtension.fromId(fallbackCategory);
    List<DeliveryModel> queuedDeliveries = [];
    bool queueQuerySucceeded = false;

    try {
      final targets = await _db
          .from('delivery_notification_targets')
          .select('delivery_id, deliveries(*)')
          .eq('motoboy_id', motoboyId)
          .lte('available_from', DateTime.now().toIso8601String())
          .order('available_from', ascending: true)
          .limit(100);

      queuedDeliveries = (targets as List)
          .map((row) => row['deliveries'])
          .whereType<Map<String, dynamic>>()
          .where(
            (row) => row['status'] == 'pending' && row['motoboy_id'] == null,
          )
          .map(DeliveryModel.fromJson)
          .toList();
      queueQuerySucceeded = true;
    } catch (_) {
      // Se a fila ainda não existir no ambiente, ignora.
    }

    // Sempre busca as corridas pendentes do banco (fallback/comportamento geral)
    // para garantir que entregadores que ficaram online depois ou que não foram
    // incluídos na fila do trigger (ex: por GPS temporariamente nulo) ainda vejam a corrida.
    final fallbackCategories = fallbackVisibleDeliveryCategoriesForDriver(
      driverCategory,
    ).map((category) => category.info.id).toList();

    List<DeliveryModel> fallbackDeliveries = [];
    try {
      final data = await _db
          .from('deliveries')
          .select()
          .eq('status', 'pending')
          .inFilter('vehicle_category', fallbackCategories)
          .order('created_at', ascending: false)
          .limit(50);

      fallbackDeliveries = (data as List)
          .map((e) => DeliveryModel.fromJson(e))
          .where(
            (delivery) => driverCanSeeDeliveryCategoryFallback(
              driverCategory: driverCategory,
              deliveryCategory: delivery.vehicleCategory,
              deliveryDistanceKm: delivery.distanceKm,
            ),
          )
          .toList();
    } catch (_) {
      // Ignora falhas na listagem geral
    }

    if (!queueQuerySucceeded) {
      return fallbackDeliveries;
    }

    // Combina as duas listas e remove duplicatas (comparando pelo ID da entrega)
    final Map<String, DeliveryModel> combined = {};
    for (final d in queuedDeliveries) {
      combined[d.id] = d;
    }
    for (final d in fallbackDeliveries) {
      combined[d.id] = d;
    }

    return combined.values.toList();
  }

  /// Stream de novas corridas disponíveis (Realtime).
  /// Escuta a fila do próprio motoboy, incluindo updates quando a onda
  /// é liberada pelo cron (`sent_at` passa a ser preenchido).
  RealtimeChannel watchAvailableRuns({
    required String motoboyId,
    required void Function() onNewRun,
  }) {
    return _db
        .channel('available-runs-$motoboyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'delivery_notification_targets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'motoboy_id',
            value: motoboyId,
          ),
          callback: (_) => onNewRun(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'delivery_notification_targets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'motoboy_id',
            value: motoboyId,
          ),
          callback: (_) => onNewRun(),
        )
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
        .select(
          '*, motoboys(vehicle_plate, current_lat, current_lng, users(name, phone))',
        )
        .eq('motoboy_id', motoboyId)
        .inFilter('status', ['completed', 'cancelled'])
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List).map((e) => DeliveryModel.fromJson(e)).toList();
  }

  Future<List<DeliveryModel>> getRunHistoryPage({
    required String motoboyId,
    required int offset,
    int limit = 20,
  }) async {
    final data = await _db
        .from('deliveries')
        .select(
          '*, motoboys(vehicle_plate, current_lat, current_lng, users(name, phone))',
        )
        .eq('motoboy_id', motoboyId)
        .inFilter('status', ['completed', 'cancelled'])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((e) => DeliveryModel.fromJson(e)).toList();
  }

  Future<EarningsDashboard> getEarningsDashboard(String motoboyId) async {
    final since = DateTime.now()
        .subtract(const Duration(days: 180))
        .toIso8601String();
    final data = await _db
        .from('deliveries')
        .select('value, completed_at')
        .eq('motoboy_id', motoboyId)
        .eq('status', 'completed')
        .gte('completed_at', since)
        .order('completed_at', ascending: true);

    final rows = (data as List)
        .where((row) => row['completed_at'] != null)
        .map(
          (row) => (
            completedAt: DateTime.parse(row['completed_at'] as String),
            net: (row['value'] as num).toDouble(),
          ),
        )
        .toList();

    final now = DateTime.now();

    double totalForDays(int days) {
      final cutoff = now.subtract(Duration(days: days));
      return rows
          .where((row) => row.completedAt.isAfter(cutoff))
          .fold(0.0, (sum, row) => sum + row.net);
    }

    final dailyPoints = List.generate(7, (index) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - index));
      final total = rows
          .where(
            (row) =>
                row.completedAt.year == day.year &&
                row.completedAt.month == day.month &&
                row.completedAt.day == day.day,
          )
          .fold(0.0, (sum, row) => sum + row.net);
      const labels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
      return EarningsPoint(label: labels[day.weekday % 7], value: total);
    });

    final weeklyPoints = List.generate(6, (index) {
      final weekEnd = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 7 * (5 - index)));
      final weekStart = weekEnd.subtract(const Duration(days: 6));
      final total = rows
          .where(
            (row) =>
                !row.completedAt.isBefore(weekStart) &&
                !row.completedAt.isAfter(weekEnd.add(const Duration(days: 1))),
          )
          .fold(0.0, (sum, row) => sum + row.net);
      return EarningsPoint(label: 'S${index + 1}', value: total);
    });

    final monthlyPoints = List.generate(6, (index) {
      final monthDate = DateTime(now.year, now.month - (5 - index), 1);
      final total = rows
          .where(
            (row) =>
                row.completedAt.year == monthDate.year &&
                row.completedAt.month == monthDate.month,
          )
          .fold(0.0, (sum, row) => sum + row.net);
      const labels = [
        'Jan',
        'Fev',
        'Mar',
        'Abr',
        'Mai',
        'Jun',
        'Jul',
        'Ago',
        'Set',
        'Out',
        'Nov',
        'Dez',
      ];
      return EarningsPoint(label: labels[monthDate.month - 1], value: total);
    });

    return EarningsDashboard(
      today: totalForDays(1),
      week: totalForDays(7),
      month: totalForDays(30),
      dailyPoints: dailyPoints,
      weeklyPoints: weeklyPoints,
      monthlyPoints: monthlyPoints,
    );
  }

  // ── ACEITAR CORRIDA ──────────────────────────────────────
  /// Valida saldo ANTES de aceitar
  Future<void> acceptDelivery({
    required String deliveryId,
    required String motoboyId,
    required double commission,
  }) async {
    final motoboy = await fetchMotoboy(motoboyId);
    _ensureApproved(motoboy);

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

    // 2. Aceita atomicamente: só atualiza se ainda estiver 'pending'
    // Isso elimina a race condition — se dois motoboys tentarem simultaneamente,
    // apenas um consegue (o outro recebe lista vazia).
    final updated = await _db
        .from('deliveries')
        .update({
          'motoboy_id': motoboyId,
          'status': 'accepted',
          'accepted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', deliveryId)
        .eq('status', 'pending')
        .select('id');

    if ((updated as List).isEmpty) {
      throw Exception(
        'Esta corrida já foi aceita por outro entregador. Tente outra!',
      );
    }
  }

  /// Desistir de uma corrida aceita (volta a 'pending' para outro entregador pegar).
  /// Usa RPC com SECURITY DEFINER para contornar a política RLS de WITH CHECK.
  /// SQL a criar no Supabase:
  ///   CREATE OR REPLACE FUNCTION abandon_delivery(p_delivery_id uuid)
  ///   RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
  ///   BEGIN
  ///     UPDATE deliveries SET motoboy_id = NULL, status = 'pending', accepted_at = NULL
  ///     WHERE id = p_delivery_id AND motoboy_id = auth.uid() AND status = 'accepted';
  ///     IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  ///   END;$$;
  Future<void> abandonDelivery(String deliveryId) async {
    try {
      await _db.rpc('abandon_delivery', params: {'p_delivery_id': deliveryId});
    } on PostgrestException catch (e) {
      if (e.message.contains('not_found')) {
        throw Exception(
          'Esta corrida não pode ser devolvida. Verifique o status e tente novamente.',
        );
      }
      rethrow;
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
          await _db
              .from('motoboys')
              .update({
                'current_lat': pos.latitude,
                'current_lng': pos.longitude,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', motoboyId);
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
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lng2 - lng1);
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * asin(sqrt(h));
  }

  double _toRad(double deg) => deg * pi / 180;

  void _ensureApproved(MotoboyModel motoboy) {
    if (motoboy.canGoOnline) return;

    String message;
    switch (motoboy.approvalStatus) {
      case MotoboyApprovalStatus.pendingDocuments:
        message = 'Complete o cadastro documental antes de operar.';
        break;
      case MotoboyApprovalStatus.pendingReview:
        message = 'Seu cadastro ainda está em análise. Aguarde a aprovação.';
        break;
      case MotoboyApprovalStatus.rejected:
        message = 'Seu cadastro foi reprovado. Revise os documentos enviados.';
        break;
      case MotoboyApprovalStatus.approved:
        return;
    }

    final rejectionReason = motoboy.rejectionReason?.trim();
    if (rejectionReason != null && rejectionReason.isNotEmpty) {
      message = '$message Motivo: $rejectionReason';
    }

    throw Exception(message);
  }
}

class InsufficientBalanceException implements Exception {
  final String message;
  InsufficientBalanceException(this.message);
  @override
  String toString() => message;
}
