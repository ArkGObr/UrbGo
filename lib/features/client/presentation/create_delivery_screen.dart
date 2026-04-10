import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/client_providers.dart';

class CreateDeliveryScreen extends ConsumerStatefulWidget {
  const CreateDeliveryScreen({super.key});

  @override
  ConsumerState<CreateDeliveryScreen> createState() =>
      _CreateDeliveryScreenState();
}

class _CreateDeliveryScreenState extends ConsumerState<CreateDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  final _mapController = MapController();

  String _paymentMethod = 'pix';
  bool _isLoading = false;
  bool _isGeocodingPickup = false;
  bool _isGeocodingDelivery = false;

  LatLng? _pickupLatLng;
  LatLng? _deliveryLatLng;
  double? _distanceKm;
  double? _deliveryValue;
  double? _commission;

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _deliveryCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Calcula distância via fórmula de Haversine
  double _haversineDistanceKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(a.latitude)) *
            cos(_toRad(b.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * asin(sqrt(h));
  }

  double _toRad(double deg) => deg * pi / 180;

  /// Calcula valor: R$5 base + R$1,50/km
  double _calculateDeliveryValue(double distanceKm) {
    const double baseRate = 5.0;
    const double perKm = 1.50;
    return baseRate + (distanceKm * perKm);
  }

  /// Recalcula tudo quando ambos endereços estão geocodificados
  void _recalculate() {
    if (_pickupLatLng != null && _deliveryLatLng != null) {
      final dist = _haversineDistanceKm(_pickupLatLng!, _deliveryLatLng!);
      final val = _calculateDeliveryValue(dist);
      setState(() {
        _distanceKm = dist;
        _deliveryValue = val;
        _commission = val * 0.25;
      });

      // Centraliza mapa para mostrar os dois pontos
      _fitMapBounds();
    }
  }

  void _fitMapBounds() {
    if (_pickupLatLng == null || _deliveryLatLng == null) return;

    final bounds = LatLngBounds(
      _pickupLatLng!,
      _deliveryLatLng!,
    );

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (_) {
      // MapController não pronto ainda
    }
  }

  /// Geocodifica um endereço
  Future<LatLng?> _geocodeAddress(String address) async {
    final service = ref.read(geocodingServiceProvider);
    return service.geocode(address);
  }

  /// Usa localização atual para preencher pickup
  Future<void> _useCurrentLocation() async {
    setState(() => _isGeocodingPickup = true);

    try {
      // Verifica permissão
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Permissão de localização negada',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              backgroundColor: AppColors.surface,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);

      // Reverse geocode
      final service = ref.read(geocodingServiceProvider);
      final address = await service.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (mounted) {
        setState(() {
          _pickupLatLng = latLng;
          if (address != null) {
            _pickupCtrl.text = address;
          }
        });
        _recalculate();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao obter localização',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            backgroundColor: AppColors.surface,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeocodingPickup = false);
    }
  }

  /// Geocodifica o endereço de coleta
  Future<void> _geocodePickup() async {
    if (_pickupCtrl.text.trim().isEmpty) return;
    setState(() => _isGeocodingPickup = true);
    final result = await _geocodeAddress(_pickupCtrl.text.trim());
    if (mounted) {
      setState(() {
        _pickupLatLng = result;
        _isGeocodingPickup = false;
      });
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Endereço de coleta não encontrado',
              style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary),
            ),
            backgroundColor: AppColors.surface,
          ),
        );
      }
      _recalculate();
    }
  }

  /// Geocodifica o endereço de entrega
  Future<void> _geocodeDelivery() async {
    if (_deliveryCtrl.text.trim().isEmpty) return;
    setState(() => _isGeocodingDelivery = true);
    final result = await _geocodeAddress(_deliveryCtrl.text.trim());
    if (mounted) {
      setState(() {
        _deliveryLatLng = result;
        _isGeocodingDelivery = false;
      });
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Endereço de entrega não encontrado',
              style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary),
            ),
            backgroundColor: AppColors.surface,
          ),
        );
      }
      _recalculate();
    }
  }

  /// Confirma e cria a entrega
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Geocodifica se necessário
    if (_pickupLatLng == null) await _geocodePickup();
    if (_deliveryLatLng == null) await _geocodeDelivery();

    if (_pickupLatLng == null || _deliveryLatLng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Não foi possível localizar os endereços',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authNotifierProvider).valueOrNull;
      if (user == null) return;

      final delivery = await ref.read(deliveryRepositoryProvider).createDelivery(
            clientId: user.id,
            pickupAddress: _pickupCtrl.text.trim(),
            pickupLat: _pickupLatLng!.latitude,
            pickupLng: _pickupLatLng!.longitude,
            deliveryAddress: _deliveryCtrl.text.trim(),
            deliveryLat: _deliveryLatLng!.latitude,
            deliveryLng: _deliveryLatLng!.longitude,
            value: _deliveryValue!,
            paymentMethod: _paymentMethod,
          );

      // Invalida o cache de entregas
      ref.invalidate(clientDeliveriesProvider);

      if (mounted) {
        context.go('/client/tracking/${delivery.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Erro ao criar entrega: ${e.toString()}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Nova Entrega', style: AppTypography.h3),
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: AppSpacing.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.lg),

                    // ── Endereço de coleta ───────────────
                    Text('Coleta', style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _pickupCtrl,
                      textInputAction: TextInputAction.next,
                      onEditingComplete: _geocodePickup,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Endereço de coleta',
                        prefixIcon: _isGeocodingPickup
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : Icon(
                                _pickupLatLng != null
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_on_rounded,
                                color: _pickupLatLng != null
                                    ? AppColors.primary
                                    : AppColors.textTertiary,
                                size: 20,
                              ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.my_location_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          tooltip: 'Usar minha localização',
                          onPressed: _useCurrentLocation,
                        ),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Endereço de coleta obrigatório'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Endereço de entrega ──────────────
                    Text('Entrega', style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _deliveryCtrl,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: _geocodeDelivery,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Endereço de entrega',
                        prefixIcon: _isGeocodingDelivery
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : Icon(
                                _deliveryLatLng != null
                                    ? Icons.check_circle_rounded
                                    : Icons.location_on_rounded,
                                color: _deliveryLatLng != null
                                    ? AppColors.primary
                                    : AppColors.textTertiary,
                                size: 20,
                              ),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Endereço de entrega obrigatório'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.xl2),
                  ],
                ),
              ),

              // ── Preview do mapa ───────────────────
              SizedBox(
                height: 200,
                child: _buildMapPreview(),
              ),

              Padding(
                padding: AppSpacing.screenPaddingFull,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.xl2),

                    // ── Forma de pagamento ──────────────
                    Text('Pagamento', style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _PaymentChip(
                          icon: Icons.money_rounded,
                          label: 'Dinheiro',
                          value: 'cash',
                          selected: _paymentMethod == 'cash',
                          onTap: () =>
                              setState(() => _paymentMethod = 'cash'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _PaymentChip(
                          icon: Icons.pix_rounded,
                          label: 'PIX',
                          value: 'pix',
                          selected: _paymentMethod == 'pix',
                          onTap: () =>
                              setState(() => _paymentMethod = 'pix'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _PaymentChip(
                          icon: Icons.credit_card_rounded,
                          label: 'Maquininha',
                          value: 'card',
                          selected: _paymentMethod == 'card',
                          onTap: () =>
                              setState(() => _paymentMethod = 'card'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl3),

                    // ── Resumo de valor ─────────────────
                    if (_deliveryValue != null) ...[
                      Container(
                        padding: AppSpacing.cardPadding,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                              color: AppColors.surfaceBorder, width: 0.5),
                        ),
                        child: Column(
                          children: [
                            _SummaryRow(
                              label: 'Distância',
                              value: '${_distanceKm!.toStringAsFixed(1)} km',
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const Divider(color: AppColors.surfaceBorder),
                            const SizedBox(height: AppSpacing.sm),
                            _SummaryRow(
                              label: 'Valor da entrega',
                              value:
                                  CurrencyFormatter.format(_deliveryValue!),
                              valueStyle: AppTypography.numericMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            _SummaryRow(
                              label: 'Taxa de serviço (25%)',
                              value:
                                  CurrencyFormatter.format(_commission!),
                              valueStyle:
                                  AppTypography.bodyMedium.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl3),
                    ],

                    // ── Botão confirmar ─────────────────
                    PrimaryButton(
                      label: 'Confirmar Pedido',
                      onPressed: _isLoading ||
                              (_pickupLatLng == null &&
                                  _pickupCtrl.text.trim().isEmpty)
                          ? null
                          : _submit,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: AppSpacing.xl2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapPreview() {
    final center = _pickupLatLng ?? const LatLng(-23.5505, -46.6333);

    return ClipRRect(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: _pickupLatLng != null && _deliveryLatLng != null
              ? 12
              : 13,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.urbgo.app',
          ),
          // Overlay escuro no mapa
          ColoredBox(color: Colors.black.withValues(alpha: 0.3), child: const SizedBox.expand()),
          if (_pickupLatLng != null || _deliveryLatLng != null)
            MarkerLayer(
              markers: [
                if (_pickupLatLng != null)
                  Marker(
                    point: _pickupLatLng!,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.radio_button_on_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                if (_deliveryLatLng != null)
                  Marker(
                    point: _deliveryLatLng!,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.error,
                      size: 32,
                    ),
                  ),
              ],
            ),
          if (_pickupLatLng != null && _deliveryLatLng != null)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [_pickupLatLng!, _deliveryLatLng!],
                  color: AppColors.primary.withValues(alpha: 0.6),
                  strokeWidth: 3,
                  isDotted: true,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Payment Chip ─────────────────────────────────────────────
class _PaymentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryDeep : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.surfaceBorder,
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.primary : AppColors.textTertiary,
                size: 22,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary Row ──────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium),
        Text(value, style: valueStyle ?? AppTypography.bodyMedium),
      ],
    );
  }
}
