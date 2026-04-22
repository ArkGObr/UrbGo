import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/delivery_repository.dart';
import '../data/rating_repository.dart';
import 'delivery_model.dart';
import '../../../core/services/geocoding_service.dart';

final deliveryRepositoryProvider =
    Provider<DeliveryRepository>((ref) => DeliveryRepository());

final geocodingServiceProvider =
    Provider<GeocodingService>((ref) => GeocodingService());

/// Lista de entregas do cliente (todas)
final clientDeliveriesProvider =
    FutureProvider<List<DeliveryModel>>((ref) async {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) return [];
  try {
    return await ref.read(deliveryRepositoryProvider).getClientDeliveries(user.id);
  } catch (e, stack) {
    print('Erro em clientDeliveriesProvider: $e\n$stack');
    throw Exception('Erro ao carregar: $e');
  }
});

/// Entregas ativas do cliente (pending, accepted, in_progress)
final activeClientDeliveriesProvider =
    FutureProvider<List<DeliveryModel>>((ref) async {
  final all = await ref.watch(clientDeliveriesProvider.future);
  return all.where((d) => d.isActive).toList();
});

/// Entrega específica em tempo real (via stream)
final deliveryStreamProvider =
    StreamProvider.family<DeliveryModel, String>(
  (ref, deliveryId) =>
      ref.read(deliveryRepositoryProvider).watchDelivery(deliveryId),
);

/// Histórico de entregas (concluídas e canceladas)
final clientHistoryProvider = FutureProvider<List<DeliveryModel>>((ref) async {
  final all = await ref.watch(clientDeliveriesProvider.future);
  return all.where((d) => !d.isActive).toList();
});

/// Mapa deliveryId → nota dada pelo cliente (1-5)
final clientRatingsProvider = FutureProvider<Map<String, int>>((ref) async {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) return {};
  return RatingRepository().getClientRatings(user.id);
});
