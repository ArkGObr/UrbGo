import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../client/domain/delivery_model.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/motoboy_providers.dart';

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
  StreamSubscription<Position>? _positionStream;
  bool _isProcessing = false;
  DeliveryModel? _delivery;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _startPositionStream();
    _loadDelivery();
  }

  Future<void> _loadDelivery() async {
    try {
      final data = await Supabase.instance.client
          .from('deliveries')
          .select()
          .eq('id', widget.deliveryId)
          .single();
      if (mounted) {
        setState(() {
          _delivery = DeliveryModel.fromJson(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startPositionStream() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      ref.read(_myPositionProvider.notifier).state =
          LatLng(pos.latitude, pos.longitude);
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
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
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
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
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.urbgo.app',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [pickupLatLng, deliveryLatLng],
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
              ],
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
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Status
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: delivery.status.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: delivery.status.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(delivery.status.icon,
                              color: delivery.status.color, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            delivery.status.label,
                            style: AppTypography.h4.copyWith(
                              color: delivery.status.color,
                            ),
                          ),
                        ],
                      ),
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

                    // Botões de ação
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
