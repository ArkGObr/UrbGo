import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../client/domain/delivery_model.dart';
import '../../shared/models/transaction_model.dart';
import '../data/motoboy_repository.dart';
import 'earnings_dashboard.dart';
import 'motoboy_model.dart';

final motoboyRepositoryProvider = Provider<MotoboyRepository>(
  (ref) => MotoboyRepository(),
);

/// Dados do motoboy em tempo real
final motoboyStreamProvider = StreamProvider<MotoboyModel>((ref) async* {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) throw Exception('Não autenticado');

  // Verifica se o registro motoboys existe; se não, cria (fallback caso a trigger falhe)
  final exists = await Supabase.instance.client
      .from('motoboys')
      .select('id')
      .eq('id', user.id)
      .maybeSingle();

  if (exists == null) {
    await Supabase.instance.client.from('motoboys').upsert({
      'id': user.id,
      'wallet_balance': 0.0,
      'is_online': false,
    });
  }

  yield* ref.read(motoboyRepositoryProvider).watchMotoboy(user.id);
});

/// Corridas disponíveis (fetch com posição, filtrado pela categoria do motoboy)
final availableRunsProvider = FutureProvider<List<DeliveryModel>>((ref) async {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) return [];
  final pos = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
  return ref
      .read(motoboyRepositoryProvider)
      .getAvailableRuns(
        motoboyId: user.id,
        lat: pos.latitude,
        lng: pos.longitude,
        radiusKm:
            50.0, // Aumentado para 50km para garantir que encontre num raio maior
      );
});

/// Corrida ativa do motoboy (em tempo real)
final activeRunProvider = StreamProvider.family<DeliveryModel?, String>((
  ref,
  motoboyId,
) {
  return Supabase.instance.client
      .from('deliveries')
      .stream(primaryKey: ['id'])
      .eq('motoboy_id', motoboyId)
      .map((rows) {
        final active = rows
            .where(
              (r) => r['status'] == 'accepted' || r['status'] == 'in_progress',
            )
            .toList();
        return active.isEmpty ? null : DeliveryModel.fromJson(active.first);
      });
});

/// Transações do motoboy (últimas 30)
final transactionsProvider = FutureProvider<List<TransactionModel>>((
  ref,
) async {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) return [];
  final data = await Supabase.instance.client
      .from('transactions')
      .select()
      .eq('motoboy_id', user.id)
      .order('created_at', ascending: false)
      .limit(30);
  return (data as List).map((e) => TransactionModel.fromJson(e)).toList();
});

/// Histórico de corridas realizadas (finalizadas ou canceladas)
final runHistoryProvider = FutureProvider<List<DeliveryModel>>((ref) async {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) return [];
  return ref.read(motoboyRepositoryProvider).getRunHistory(user.id);
});

final earningsDashboardProvider = FutureProvider<EarningsDashboard>((
  ref,
) async {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) {
    return const EarningsDashboard(
      today: 0,
      week: 0,
      month: 0,
      dailyPoints: [],
      weeklyPoints: [],
      monthlyPoints: [],
    );
  }
  return ref.read(motoboyRepositoryProvider).getEarningsDashboard(user.id);
});
