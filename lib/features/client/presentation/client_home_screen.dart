import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/connectivity_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/delivery_card.dart';
import '../../shared/widgets/micro_interactions.dart';
import '../domain/client_providers.dart';

class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(clientDeliveriesProvider);

    return OfflineBanner(
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: AppSpacing.sm),
            RichText(
              text: TextSpan(
                style: AppTypography.h2,
                children: [
                  const TextSpan(text: 'Urb'),
                  TextSpan(
                    text: 'Go',
                    style: AppTypography.h2.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            tooltip: 'Sair',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: Container(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGlow,
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/client/create'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textInverse,
          elevation: 0,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'Nova Entrega',
            style: AppTypography.buttonSmall.copyWith(
              color: AppColors.textInverse,
            ),
          ),
        ),
      ),
      body: deliveriesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
        error: (e, _) => _ErrorState(
          onRetry: () => ref.invalidate(clientDeliveriesProvider),
          e: e,
        ),
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return const _EmptyState();
          }

          // Separar ativas e histórico
          final active = deliveries.where((d) => d.isActive).toList();
          final history = deliveries.where((d) => !d.isActive).toList();

          // Entrega com motoboy (accepted ou in_progress)
          final tracked = active.where((d) => d.motoboyId != null).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(clientDeliveriesProvider);
              await ref.read(clientDeliveriesProvider.future);
            },
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView(
              padding: AppSpacing.screenPaddingFull,
              children: [
                // Mini-mapa de rastreamento
                if (tracked.isNotEmpty) ...[
                  _ActiveDeliveryMap(delivery: tracked.first),
                  const SizedBox(height: AppSpacing.xl2),
                ],

                // Entregas ativas
                if (active.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Em andamento',
                    count: active.length,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...active.asMap().entries.map(
                    (e) => DeliveryCard(delivery: e.value, index: e.key),
                  ),
                  const SizedBox(height: AppSpacing.xl2),
                ],

                // Histórico
                if (history.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Histórico',
                    count: history.length,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...history.asMap().entries.map(
                    (e) => DeliveryCard(
                      delivery: e.value,
                      index: e.key + active.length,
                    ),
                  ),
                ],

                // Espaço para FAB
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    )); // OfflineBanner
  }
}

// ── Section Header ────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: AppTypography.h3),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            '$count',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.primary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl4),
        child: FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: const Icon(
                  Icons.two_wheeler_rounded,
                  color: AppColors.textTertiary,
                  size: 40,
                ),
              ),
              const SizedBox(height: AppSpacing.xl2),
              Text(
                'Nenhuma entrega ainda',
                style: AppTypography.h3.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Toque no botão abaixo para\ncriar seu primeiro pedido',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error State ───────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final Object e;

  const _ErrorState({required this.onRetry, required this.e});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Erro: ${e.toString()}',
              style: AppTypography.h4.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl2),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
              label: Text(
                'Tentar novamente',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mini-mapa de rastreamento do entregador ────────────────────
class _ActiveDeliveryMap extends StatefulWidget {
  final dynamic delivery; // DeliveryModel

  const _ActiveDeliveryMap({required this.delivery});

  @override
  State<_ActiveDeliveryMap> createState() => _ActiveDeliveryMapState();
}

class _ActiveDeliveryMapState extends State<_ActiveDeliveryMap> {
  RealtimeChannel? _channel;
  LatLng? _motoboyPos;

  @override
  void initState() {
    super.initState();
    final d = widget.delivery;

    // Posição inicial do motoboy (se disponível no modelo)
    if (d.motoboyLat != null && d.motoboyLng != null) {
      _motoboyPos = LatLng(d.motoboyLat!, d.motoboyLng!);
    }

    // Escutar atualizações de posição em tempo real
    if (d.motoboyId != null) {
      _channel = Supabase.instance.client
          .channel('home_motoboy_${d.motoboyId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'motoboys',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: d.motoboyId,
            ),
            callback: (payload) {
              final lat = payload.newRecord['current_lat'];
              final lng = payload.newRecord['current_lng'];
              if (lat != null && lng != null && mounted) {
                setState(() {
                  _motoboyPos = LatLng(
                    (lat as num).toDouble(),
                    (lng as num).toDouble(),
                  );
                });
              }
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final pickupLatLng = LatLng(d.pickupLat, d.pickupLng);
    final deliveryLatLng = LatLng(d.deliveryLat, d.deliveryLng);
    final center = _motoboyPos ?? pickupLatLng;

    return GestureDetector(
      onTap: () => context.push('/client/tracking/${d.id}'),
      child: FadeSlideIn(
        delay: const Duration(milliseconds: 100),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Mapa
              FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: AppConstants.mapTileUrl,
                    userAgentPackageName: 'com.urbgo.app',
                  ),
                  MarkerLayer(
                    markers: [
                      // Coleta
                      Marker(
                        point: pickupLatLng,
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.radio_button_on_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      // Entrega
                      Marker(
                        point: deliveryLatLng,
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.flag_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      // Motoboy
                      if (_motoboyPos != null)
                        Marker(
                          point: _motoboyPos!,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.4),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.two_wheeler_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // Label overlay
              Positioned(
                left: AppSpacing.md,
                top: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Rastreando entregador',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Tap hint
              Positioned(
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Acompanhar',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
