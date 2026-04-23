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
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/services/route_service.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../data/rating_repository.dart';
import '../domain/client_providers.dart';
import '../domain/delivery_model.dart';
import 'widgets/rating_bottom_sheet.dart';

// Provider local para ETA em tempo real (motoboy → próximo destino)
final _etaProvider = StateProvider<String?>((ref) => null);

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
  bool _hasShownRating = false;
  bool _hasCheckedInitialRating = false;
  final RouteService _routeService = RouteService();
  DateTime? _lastEtaFetch;
  String? _routeCacheKey;

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
    _motoboyTo = newPos;

    _latAnim = Tween<double>(begin: from.latitude, end: newPos.latitude)
        .animate(
          CurvedAnimation(parent: _motoboyAnimCtrl, curve: Curves.easeInOut),
        );
    _lngAnim = Tween<double>(begin: from.longitude, end: newPos.longitude)
        .animate(
          CurvedAnimation(parent: _motoboyAnimCtrl, curve: Curves.easeInOut),
        );

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
    _motoboyChannel = ref
        .read(deliveryRepositoryProvider)
        .watchMotoboyLocation(
          motoboyId: motoboyId,
          onUpdate: (lat, lng) {
            if (mounted) {
              final pos = LatLng(lat, lng);
              setState(() => _animateMotoboyTo(pos));
              _updateEta(pos);
            }
          },
        );
  }

  void _updateEta(LatLng motoboyPos) {
    final now = DateTime.now();
    // Atualiza ETA no máximo a cada 30s para não sobrecarregar a API
    if (_lastEtaFetch != null &&
        now.difference(_lastEtaFetch!).inSeconds < 30) {
      return;
    }
    _lastEtaFetch = now;

    // Pega o destino correto a partir do stream atual
    final delivery = ref
        .read(deliveryStreamProvider(widget.deliveryId))
        .valueOrNull;
    if (delivery == null) return;

    final stops = <LatLng>[
      motoboyPos,
      if (delivery.status == DeliveryStatus.accepted)
        LatLng(delivery.pickupLat, delivery.pickupLng)
      else ...[
        if (delivery.extraStopLat != null && delivery.extraStopLng != null)
          LatLng(delivery.extraStopLat!, delivery.extraStopLng!),
        LatLng(delivery.deliveryLat, delivery.deliveryLng),
      ],
    ];

    _routeService
        .getRouteWithStops(stops)
        .then((result) {
          if (!mounted) return;
          final mins = (result.durationSeconds / 60).ceil();
          ref.read(_etaProvider.notifier).state = mins <= 1
              ? 'Chegando'
              : '~ $mins min';
        })
        .catchError((_) {});
  }

  Future<void> _loadRoute(DeliveryModel delivery) async {
    try {
      final routeService = ref.read(routeServiceProvider);
      final stops = <LatLng>[
        LatLng(delivery.pickupLat, delivery.pickupLng),
        if (delivery.extraStopLat != null && delivery.extraStopLng != null)
          LatLng(delivery.extraStopLat!, delivery.extraStopLng!),
        LatLng(delivery.deliveryLat, delivery.deliveryLng),
      ];
      final points = await routeService
          .getRouteWithStops(stops)
          .then((result) => result.points);
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

  Future<void> _cancelDelivery(
    String deliveryId, {
    bool withPenaltyWarning = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Cancelar entrega?', style: AppTypography.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (withPenaltyWarning) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'O entregador já foi aceito. Cancelamentos frequentes podem afetar sua conta.',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              'Esta ação não pode ser desfeita.',
              style: AppTypography.bodyMedium,
            ),
          ],
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
              style: AppTypography.labelLarge.copyWith(color: AppColors.error),
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

  void _onStatusChanged(DeliveryStatus prev, DeliveryStatus next) {
    if (!mounted) return;
    switch (next) {
      case DeliveryStatus.accepted:
        AppToast.show(
          context,
          title: 'Entregador a caminho!',
          subtitle: 'Seu pedido foi aceito',
          type: AppToastType.info,
        );
      case DeliveryStatus.inProgress:
        AppToast.show(
          context,
          title: 'Pacote coletado!',
          subtitle: 'Seu pedido está sendo entregue',
          type: AppToastType.success,
        );
      case DeliveryStatus.completed:
        AppToast.show(
          context,
          title: 'Entrega concluída!',
          subtitle: 'Seu pedido chegou com sucesso',
          type: AppToastType.success,
          duration: const Duration(seconds: 5),
        );
      case DeliveryStatus.cancelled:
        AppToast.show(
          context,
          title: 'Entrega cancelada',
          subtitle: 'Entre em contato com o suporte se precisar de ajuda',
          type: AppToastType.error,
          duration: const Duration(seconds: 6),
        );
      default:
        break;
    }
  }

  void _maybeShowRating(DeliveryModel delivery) {
    if (_hasShownRating) return;
    if (delivery.motoboyId == null) return;
    _hasShownRating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final alreadyRated = await RatingRepository().hasRated(delivery.id);
      if (!mounted) return;
      if (alreadyRated) return;
      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      await RatingBottomSheet.show(context, ref, delivery);
      if (!mounted || !context.mounted) return;
      ref.invalidate(clientDeliveriesProvider);
      // ignore: use_build_context_synchronously
      context.go('/client/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    final deliveryAsync = ref.watch(deliveryStreamProvider(widget.deliveryId));

    ref.listen<AsyncValue<DeliveryModel>>(
      deliveryStreamProvider(widget.deliveryId),
      (prev, next) {
        final prevStatus = prev?.valueOrNull?.status;
        final nextStatus = next.valueOrNull?.status;
        if (prevStatus != null &&
            nextStatus != null &&
            prevStatus != nextStatus) {
          _onStatusChanged(prevStatus, nextStatus);
          if (nextStatus == DeliveryStatus.completed) {
            final delivery = next.valueOrNull;
            if (delivery != null) _maybeShowRating(delivery);
          }
        }
      },
    );

    final etaText = ref.watch(_etaProvider);

    return deliveryAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
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
        final routeKey = [
          delivery.status.dbValue,
          delivery.pickupLat,
          delivery.pickupLng,
          delivery.extraStopLat,
          delivery.extraStopLng,
          delivery.deliveryLat,
          delivery.deliveryLng,
        ].join('|');
        if (_routePoints.isEmpty || _routeCacheKey != routeKey) {
          _routeCacheKey = routeKey;
          _loadRoute(delivery);
        }

        // Caso a tela abra com a entrega já concluída (sem transição de status)
        if (delivery.status == DeliveryStatus.completed &&
            !_hasCheckedInitialRating) {
          _hasCheckedInitialRating = true;
          _maybeShowRating(delivery);
        }

        // Usa posição do motoboy do modelo se o realtime ainda não atualizou
        if (_motoboyTo == null &&
            delivery.motoboyLat != null &&
            delivery.motoboyLng != null) {
          _motoboyTo = LatLng(delivery.motoboyLat!, delivery.motoboyLng!);
        }

        final pickupLatLng = LatLng(delivery.pickupLat, delivery.pickupLng);
        final extraStopLatLng =
            delivery.extraStopLat != null && delivery.extraStopLng != null
            ? LatLng(delivery.extraStopLat!, delivery.extraStopLng!)
            : null;
        final deliveryLatLng = LatLng(
          delivery.deliveryLat,
          delivery.deliveryLng,
        );

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
                              urlTemplate: AppConstants.mapTileUrl,
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
                                          color: AppColors.primary.withValues(
                                            alpha: 0.4,
                                          ),
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
                                if (extraStopLatLng != null)
                                  Marker(
                                    point: extraStopLatLng,
                                    width: 40,
                                    height: 40,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF9800),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFFF9800,
                                            ).withValues(alpha: 0.4),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.add_location_alt_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
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
                                          color: AppColors.error.withValues(
                                            alpha: 0.4,
                                          ),
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
                                            color: AppColors.primary.withValues(
                                              alpha: 0.4,
                                            ),
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        delivery.vehicleCategory.info.icon,
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
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
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
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
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
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                  border: Border(
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
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
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
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  delivery.vehicleCategory.info.icon,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      delivery.motoboyName ?? 'Entregador',
                                      style: AppTypography.h4,
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        VehicleBadge(
                                          category: delivery.vehicleCategory,
                                        ),
                                        if (delivery.motoboyPlate != null) ...[
                                          const SizedBox(width: AppSpacing.xs),
                                          Text(
                                            delivery.motoboyPlate!,
                                            style: AppTypography.mono.copyWith(
                                              color: AppColors.primary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                        if (delivery.motoboyAvgRating != null &&
                                            (delivery.motoboyTotalRatings ??
                                                    0) >
                                                0) ...[
                                          const SizedBox(width: AppSpacing.sm),
                                          const Icon(
                                            Icons.star_rounded,
                                            size: 12,
                                            color: Color(0xFFFFC107),
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            delivery.motoboyAvgRating!
                                                .toStringAsFixed(1),
                                            style: AppTypography.labelSmall
                                                .copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 11,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: delivery.motoboyReputation.color
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.full,
                                        ),
                                        border: Border.all(
                                          color: delivery
                                              .motoboyReputation
                                              .color
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            delivery.motoboyReputation.icon,
                                            size: 13,
                                            color: delivery
                                                .motoboyReputation
                                                .color,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '${delivery.motoboyReputation.label} • ${delivery.motoboyReputation.summary}',
                                              style: AppTypography.labelSmall
                                                  .copyWith(
                                                    color: delivery
                                                        .motoboyReputation
                                                        .color,
                                                    fontSize: 10,
                                                  ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // ETA chip
                              if (etaText != null &&
                                  delivery.status != DeliveryStatus.completed &&
                                  delivery.status != DeliveryStatus.cancelled)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryDeep,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.xs,
                                    ),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        size: 12,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        etaText,
                                        style: AppTypography.labelSmall
                                            .copyWith(
                                              color: AppColors.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Text(
                                  CurrencyFormatter.format(delivery.value),
                                  style: AppTypography.numericLarge,
                                ),
                            ],
                          ),
                          // Botão de chat (apenas quando ativo)
                          if (delivery.motoboyId != null &&
                              delivery.status != DeliveryStatus.completed &&
                              delivery.status != DeliveryStatus.cancelled) ...[
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 16,
                                ),
                                label: const Text('Falar com o entregador'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.sm,
                                  ),
                                  textStyle: AppTypography.labelLarge,
                                ),
                                onPressed: () {
                                  final name = Uri.encodeComponent(
                                    delivery.motoboyName ?? 'Entregador',
                                  );
                                  context.push(
                                    '/client/chat/${delivery.id}?name=$name',
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(color: AppColors.surfaceBorder),
                          const SizedBox(height: AppSpacing.md),
                        ] else ...[
                          Row(
                            children: [
                              Text('Valor', style: AppTypography.bodyMedium),
                              if (delivery.distanceKm != null) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '${delivery.distanceKm!.toStringAsFixed(1)} km',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
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
                        if (delivery.extraStopAddress != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _TrackingAddressRow(
                            icon: Icons.add_location_alt_rounded,
                            iconColor: const Color(0xFFFF9800),
                            label: 'Parada extra',
                            address: delivery.extraStopAddress!,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _TrackingAddressRow(
                          icon: Icons.location_on_rounded,
                          iconColor: AppColors.error,
                          label: 'Entrega',
                          address: delivery.deliveryAddress,
                        ),

                        // Foto de confirmação de entrega
                        if (delivery.status == DeliveryStatus.completed &&
                            delivery.deliveryPhotoUrl != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(color: AppColors.surfaceBorder),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Confirmação de entrega',
                            style: AppTypography.labelLarge,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: Image.network(
                              delivery.deliveryPhotoUrl!,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 80,
                                color: AppColors.surfaceBorder,
                                child: const Icon(
                                  Icons.broken_image_rounded,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ],

                        // Botão cancelar com aviso de penalidade se necessário
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
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                              ),
                              onPressed: _isCancelling
                                  ? null
                                  : () => _cancelDelivery(
                                      delivery.id,
                                      withPenaltyWarning:
                                          delivery.isCancelWithPenaltyWarning,
                                    ),
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
                                      style: AppTypography.button.copyWith(
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
