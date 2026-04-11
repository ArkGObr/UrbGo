import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../domain/client_providers.dart';
import '../domain/delivery_model.dart';


class TrackingScreen extends ConsumerStatefulWidget {
  final String deliveryId;

  const TrackingScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  RealtimeChannel? _motoboyChannel;

  // Animação suave do marcador do motoboy
  late AnimationController _motoboyAnimCtrl;
  late Animation<double> _latAnim;
  late Animation<double> _lngAnim;
  LatLng? _motoboyTo;

  List<LatLng> _routePoints = [];
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _motoboyAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _latAnim = const AlwaysStoppedAnimation(0);
    _lngAnim = const AlwaysStoppedAnimation(0);
  }

  void _animateMotoboyTo(LatLng newPos) {
    final from = _motoboyTo ?? newPos;
    _motoboyTo   = newPos;

    _latAnim = Tween<double>(begin: from.latitude,  end: newPos.latitude)
        .animate(CurvedAnimation(parent: _motoboyAnimCtrl, curve: Curves.easeInOut));
    _lngAnim = Tween<double>(begin: from.longitude, end: newPos.longitude)
        .animate(CurvedAnimation(parent: _motoboyAnimCtrl, curve: Curves.easeInOut));

    _motoboyAnimCtrl.forward(from: 0);
  }

  LatLng? get _currentMotoboyPos {
    if (_motoboyTo == null) return null;
    if (!_motoboyAnimCtrl.isAnimating) return _motoboyTo;
    return LatLng(_latAnim.value, _lngAnim.value);
  }

  @override
  void dispose() {
    _motoboyChannel?.unsubscribe();
    _motoboyAnimCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _startMotoboyTracking(String motoboyId) {
    _motoboyChannel?.unsubscribe();
    _motoboyChannel = ref.read(deliveryRepositoryProvider).watchMotoboyLocation(
      motoboyId: motoboyId,
      onUpdate: (lat, lng) {
        if (mounted) {
          setState(() => _animateMotoboyTo(LatLng(lat, lng)));
        }
      },
    );
  }

  Future<void> _loadRoute(DeliveryModel delivery) async {
    try {
      final routeService = ref.read(routeServiceProvider);
      final points = await routeService.getRoute(
        LatLng(delivery.pickupLat, delivery.pickupLng),
        LatLng(delivery.deliveryLat, delivery.deliveryLng),
      );
      if (mounted) {
        setState(() => _routePoints = points);
      }
    } catch (_) {
      // Fallback: linha reta
      if (mounted) {
        setState(() {
          _routePoints = [
            LatLng(delivery.pickupLat, delivery.pickupLng),
            LatLng(delivery.deliveryLat, delivery.deliveryLng),
          ];
        });
      }
    }
  }

  Future<void> _cancelDelivery(String deliveryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Cancelar entrega?', style: AppTypography.h3),
        content: Text(
          'Esta ação não pode ser desfeita.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Voltar',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancelar entrega',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      await ref.read(deliveryRepositoryProvider).cancelDelivery(deliveryId);
      ref.invalidate(clientDeliveriesProvider);
      if (mounted) context.go('/client/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao cancelar: $e',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            backgroundColor: AppColors.surface,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveryAsync = ref.watch(deliveryStreamProvider(widget.deliveryId));

    return deliveryAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go('/client/home'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: AppSpacing.lg),
              Text('Erro ao carregar entrega', style: AppTypography.h3),
            ],
          ),
        ),
      ),
      data: (delivery) {
        // Inicia tracking do motoboy se disponível
        if (delivery.motoboyId != null && _motoboyChannel == null) {
          _startMotoboyTracking(delivery.motoboyId!);
        }

        // Carrega rota se ainda não carregou
        if (_routePoints.isEmpty) {
          _loadRoute(delivery);
        }

        // Usa posição do motoboy do modelo se o realtime ainda não atualizou
        if (_motoboyTo == null &&
            delivery.motoboyLat != null &&
            delivery.motoboyLng != null) {
          _motoboyTo = LatLng(delivery.motoboyLat!, delivery.motoboyLng!);
        }

        final pickupLatLng = LatLng(delivery.pickupLat, delivery.pickupLng);
        final deliveryLatLng =
            LatLng(delivery.deliveryLat, delivery.deliveryLng);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              // ── Mapa ──────────────────────────────
              Expanded(
                child: AnimatedBuilder(
                  animation: _motoboyAnimCtrl,
                  builder: (_, __) {
                    final motoboyPos = _currentMotoboyPos;
                    return Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: pickupLatLng,
                            initialZoom: 14,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.urbgo.app',
                            ),
                            // Rota
                            if (_routePoints.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: _routePoints,
                                    color: AppColors.primary,
                                    strokeWidth: 4,
                                  ),
                                ],
                              ),
                            // Marcadores
                            MarkerLayer(
                              markers: [
                                // Coleta
                                Marker(
                                  point: pickupLatLng,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.4),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.radio_button_on_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                // Entrega
                                Marker(
                                  point: deliveryLatLng,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.error
                                              .withValues(alpha: 0.4),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.flag_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                // Motoboy (animado)
                                if (motoboyPos != null)
                                  Marker(
                                    point: motoboyPos,
                                    width: 44,
                                    height: 44,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.textInverse,
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
                                        size: 22,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // Botão voltar
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          left: AppSpacing.lg,
                          child: GestureDetector(
                            onTap: () => context.go('/client/home'),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                color: AppColors.textPrimary,
                                size: 22,
                              ),
                            ),
                          ),
                        ),

                        // Badge de status no topo
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          right: AppSpacing.lg,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(AppRadius.full),
                              border: Border.all(
                                color: delivery.status.color,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  delivery.status.icon,
                                  color: delivery.status.color,
                                  size: 14,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  delivery.status.label,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: delivery.status.color,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ── Card inferior ─────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                  border: const Border(
                    top: BorderSide(color: AppColors.surfaceBorder),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: AppSpacing.cardPaddingLarge,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Handle
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceBorder,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Motoboy info (se aceito)
                        if (delivery.motoboyId != null &&
                            delivery.status != DeliveryStatus.pending) ...[
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryDeep,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.two_wheeler_rounded,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      delivery.motoboyName ?? 'Entregador',
                                      style: AppTypography.h4,
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        VehicleBadge(
                                            category:
                                                delivery.vehicleCategory),
                                        if (delivery.motoboyPlate != null) ...[
                                          const SizedBox(width: AppSpacing.xs),
                                          Text(
                                            delivery.motoboyPlate!,
                                            style:
                                                AppTypography.mono.copyWith(
                                              color: AppColors.primary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                CurrencyFormatter.format(delivery.value),
                                style: AppTypography.numericLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(color: AppColors.surfaceBorder),
                          const SizedBox(height: AppSpacing.md),
                        ] else ...[
                          Row(
                            children: [
                              Text('Valor', style: AppTypography.bodyMedium),
                              const Spacer(),
                              Text(
                                CurrencyFormatter.format(delivery.value),
                                style: AppTypography.numericLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Divider(color: AppColors.surfaceBorder),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // Endereços
                        _TrackingAddressRow(
                          icon: Icons.radio_button_on_rounded,
                          iconColor: AppColors.primary,
                          label: 'Coleta',
                          address: delivery.pickupAddress,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _TrackingAddressRow(
                          icon: Icons.location_on_rounded,
                          iconColor: AppColors.error,
                          label: 'Entrega',
                          address: delivery.deliveryAddress,
                        ),

                        // Botão cancelar (só se pendente)
                        if (delivery.canCancel) ...[
                          const SizedBox(height: AppSpacing.xl2),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: AppColors.error,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                ),
                              ),
                              onPressed: _isCancelling
                                  ? null
                                  : () => _cancelDelivery(delivery.id),
                              child: _isCancelling
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: AppColors.error,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Cancelar Entrega',
                                      style:
                                          AppTypography.button.copyWith(
                                        color: AppColors.error,
                                      ),
                                    ),
                            ),
                          ),
                        ],

                        // Se completado, botão de voltar
                        if (delivery.status == DeliveryStatus.completed) ...[
                          const SizedBox(height: AppSpacing.xl2),
                          PrimaryButton(
                            label: 'Voltar ao início',
                            onPressed: () {
                              ref.invalidate(clientDeliveriesProvider);
                              context.go('/client/home');
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Address Row para Tracking ─────────────────────────────────
class _TrackingAddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  const _TrackingAddressRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
