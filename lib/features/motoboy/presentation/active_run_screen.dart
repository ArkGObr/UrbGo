import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/route_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../client/domain/delivery_model.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../domain/motoboy_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Provider local para a posição do motoboy em tempo real
final _myPositionProvider = StateProvider<LatLng?>((ref) => null);

class ActiveRunScreen extends ConsumerStatefulWidget {
  final String deliveryId;

  const ActiveRunScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<ActiveRunScreen> createState() => _ActiveRunScreenState();
}

class _ActiveRunScreenState extends ConsumerState<ActiveRunScreen> {
  final MapController _mapController = MapController();
  final RouteService _routeService = RouteService();
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<ServiceStatus>? _gpsStatusSub;
  bool _isProcessing = false;
  DeliveryModel? _delivery;
  bool _isLoading = true;
  List<LatLng> _routePoints = [];
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _startPositionStream();
    _startGpsMonitor();
    _loadDelivery();
  }

  void _startGpsMonitor() {
    _gpsStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (!mounted) return;
      if (status == ServiceStatus.disabled) {
        _showGpsDisabledDialog();
      }
    });
  }

  void _showGpsDisabledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('GPS desativado', style: AppTypography.h3),
        content: Text(
          'Ative o GPS para continuar atualizando sua posição durante a entrega.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: Text(
              'Ativar GPS',
              style: AppTypography.labelLarge.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDelivery() async {
    try {
      final data = await Supabase.instance.client
          .from('deliveries')
          .select()
          .eq('id', widget.deliveryId)
          .single();
      if (!mounted) return;
      final delivery = DeliveryModel.fromJson(data);
      setState(() {
        _delivery = delivery;
        _isLoading = false;
      });

      // Carrega a rota real após ter as coordenadas
      final pickup = LatLng(delivery.pickupLat, delivery.pickupLng);
      final dest = LatLng(delivery.deliveryLat, delivery.deliveryLng);
      _loadRoute(pickup, dest);
    } catch (e, stack) {
      Logger.error('ActiveRunScreen._loadDelivery', e, stack);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRoute(LatLng from, LatLng to) async {
    if (mounted) setState(() => _routePoints = [from, to]);
    try {
      final points = await _routeService.getRoute(from, to);
      if (mounted) {
        setState(() => _routePoints = points);
        _fitBounds();
      }
    } catch (_) {}
  }

  void _fitBounds() {
    if (_delivery == null) return;
    final bool goingToPickup = _delivery!.status == DeliveryStatus.accepted;
    final dest = goingToPickup
        ? LatLng(_delivery!.pickupLat, _delivery!.pickupLng)
        : LatLng(_delivery!.deliveryLat, _delivery!.deliveryLng);
    final start = ref.read(_myPositionProvider) ??
        LatLng(_delivery!.pickupLat, _delivery!.pickupLng);
    
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(start, dest),
          padding: const EdgeInsets.all(50),
        ),
      );
    } catch (_) {}
  }

  void _startPositionStream() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Frequência maior para navegação fluida
      ),
    ).listen((pos) {
      if (!mounted) return;
      final latLng = LatLng(pos.latitude, pos.longitude);
      ref.read(_myPositionProvider.notifier).state = latLng;
      
      // Auto-centraliza se estiver no modo navegação
      if (_isNavigating) {
        _mapController.move(latLng, 18.0);
      }
    });
  }

  void _toggleNavigation() {
    setState(() => _isNavigating = !_isNavigating);
    if (_isNavigating) {
      final myPos = ref.read(_myPositionProvider);
      if (myPos != null) {
        _mapController.move(myPos, 18.0);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aguardando sinal de GPS...'), 
            backgroundColor: AppColors.surface,
          ),
        );
      }
    } else {
      _fitBounds();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _gpsStatusSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _confirmPickup(String deliveryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Confirmar Coleta?', style: AppTypography.h3),
        content: Text(
          'Confirme que você retirou o pacote no ponto de coleta.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirmar',
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isProcessing = true);
    try {
      await ref.read(motoboyRepositoryProvider).confirmPickup(deliveryId);
      await _loadDelivery(); // Recarrega dados
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.surface),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _completeDelivery(DeliveryModel delivery) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Finalizar Entrega?', style: AppTypography.h3),
        content: Text(
          'Confirme que a entrega foi realizada com sucesso.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Finalizar',
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isProcessing = true);
    try {
      await ref.read(motoboyRepositoryProvider).completeDelivery(delivery.id);
      ref.invalidate(availableRunsProvider);
      ref.invalidate(motoboyStreamProvider);
      if (mounted) {
        final earnings = delivery.value - delivery.commission;
        await _showSuccessDialog(earnings, delivery.commission);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.surface),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showSuccessDialog(double earnings, double commission) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.primary, size: 40),
            ),
            const SizedBox(height: AppSpacing.xl2),
            Text('Entrega Concluída!', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Valor da corrida', style: AppTypography.bodyMedium),
                      Text(
                        CurrencyFormatter.format(earnings + commission),
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Comissão (25%)', style: AppTypography.bodySmall),
                      Text(
                        '- ${CurrencyFormatter.format(commission)}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(color: AppColors.surfaceBorder),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Você recebeu', style: AppTypography.labelLarge),
                      Text(
                        CurrencyFormatter.format(earnings),
                        style: AppTypography.numericLarge,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl2),
            PrimaryButton(
              label: 'Voltar ao início',
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/motoboy/home');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myPos = ref.watch(_myPositionProvider);

    if (_isLoading || _delivery == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final delivery = _delivery!;
    final pickupLatLng = LatLng(delivery.pickupLat, delivery.pickupLng);
    final deliveryLatLng = LatLng(delivery.deliveryLat, delivery.deliveryLng);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Mapa ──────────────────────────────
          Expanded(
            flex: 2,
            child: Stack(
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
                    MarkerLayer(
                      markers: [
                        // Coleta
                        Marker(
                          point: pickupLatLng,
                          width: 36,
                          height: 36,
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
                            child: const Icon(Icons.store_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                        // Entrega
                        Marker(
                          point: deliveryLatLng,
                          width: 36,
                          height: 36,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.flag_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                        // Minha posição
                        if (myPos != null)
                          Marker(
                            point: myPos,
                            width: 44,
                            height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.info,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.info.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.two_wheeler_rounded,
                                color: AppColors.info,
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
                    onTap: () => context.go('/motoboy/home'),
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
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary, size: 22),
                    ),
                  ),
                ),

                // Botão navegar (estilo Uber)
                Positioned(
                  bottom: AppSpacing.lg,
                  right: AppSpacing.lg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Re-center
                      if (myPos != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: GestureDetector(
                            onTap: () {
                              _mapController.move(myPos, 16);
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.my_location_rounded,
                                color: AppColors.info,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      // Navegar GPS
                      GestureDetector(
                        onTap: _toggleNavigation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _isNavigating ? AppColors.error : AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            boxShadow: [
                              BoxShadow(
                                color: (_isNavigating ? AppColors.error : AppColors.primary).withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isNavigating ? Icons.close_rounded : Icons.navigation_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isNavigating ? 'Sair da Navegação' : 'Navegar',
                                style: AppTypography.labelLarge.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    if (!_isNavigating) ...[
                      // Categoria + status
                      Row(
                        children: [
                          VehicleBadge(category: delivery.vehicleCategory),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: delivery.status.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadius.full),
                              border: Border.all(
                                color: delivery.status.color.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(delivery.status.icon,
                                    color: delivery.status.color, size: 14),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  delivery.status.label,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: delivery.status.color,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Valor
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

                      // Endereços
                      _AddressRow(
                        icon: Icons.store_rounded,
                        iconColor: AppColors.error,
                        label: 'Coleta',
                        address: delivery.pickupAddress,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _AddressRow(
                        icon: Icons.flag_rounded,
                        iconColor: AppColors.primary,
                        label: 'Entrega',
                        address: delivery.deliveryAddress,
                      ),
                      const SizedBox(height: AppSpacing.xl2),
                    ],

                    // Botões de ação SEMPRE VISÍVEIS no modo direção
                    if (delivery.status == DeliveryStatus.accepted)
                      PrimaryButton(
                        label: '✓ Confirmar Coleta',
                        onPressed: _isProcessing
                            ? null
                            : () => _confirmPickup(delivery.id),
                        isLoading: _isProcessing,
                      ),
                    if (delivery.status == DeliveryStatus.inProgress)
                      PrimaryButton(
                        label: '✓ Finalizar Entrega',
                        onPressed: _isProcessing
                            ? null
                            : () => _completeDelivery(delivery),
                        isLoading: _isProcessing,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Address Row ──────────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  const _AddressRow({
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
