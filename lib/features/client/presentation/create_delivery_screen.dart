import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/services/route_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/category_selector.dart';
import '../../shared/widgets/price_preview_card.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/client_providers.dart';

class CreateDeliveryScreen extends ConsumerStatefulWidget {
  final VehicleCategoryInfo? initialCategory;

  const CreateDeliveryScreen({
    super.key,
    this.initialCategory,
  });

  @override
  ConsumerState<CreateDeliveryScreen> createState() =>
      _CreateDeliveryScreenState();
}

class _CreateDeliveryScreenState extends ConsumerState<CreateDeliveryScreen> {
  final _pickupCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  final _mapController = MapController();
  final _pickupFocus = FocusNode();
  final _deliveryFocus = FocusNode();

  // ── Stepper ──────────────────────────────────────────────
  int _step = 0; // 0: Veículo, 1: Endereços, 2: Confirmar

  // ── Categoria ─────────────────────────────────────────────
  VehicleCategoryInfo? _selectedCategory;

  // ── Endereços ─────────────────────────────────────────────
  String _paymentMethod = 'pix';
  bool _isLoading = false;

  LatLng? _pickupLatLng;
  LatLng? _deliveryLatLng;
  double? _distanceKm;
  double? _deliveryValue;

  List<AddressSuggestion> _pickupSuggestions = [];
  List<AddressSuggestion> _deliverySuggestions = [];
  bool _loadingPickupSuggestions = false;
  bool _loadingDeliverySuggestions = false;
  Timer? _pickupDebounce;
  Timer? _deliveryDebounce;

  final RouteService _routeService = RouteService();
  List<LatLng> _routePoints = [];
  RouteResult? _routeResult;

  bool _settingPickup = false;
  bool _settingDelivery = false;

  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory;
      _step = 1; // Skip the vehicle selection step!
    }
    _fetchUserLocation();
    _pickupCtrl.addListener(_onPickupChanged);
    _deliveryCtrl.addListener(_onDeliveryChanged);
    _pickupFocus.addListener(() {
      if (!_pickupFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _pickupSuggestions = []);
        });
      }
    });
    _deliveryFocus.addListener(() {
      if (!_deliveryFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _deliverySuggestions = []);
        });
      }
    });
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _deliveryCtrl.dispose();
    _mapController.dispose();
    _pickupFocus.dispose();
    _deliveryFocus.dispose();
    _pickupDebounce?.cancel();
    _deliveryDebounce?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // Location
  // ─────────────────────────────────────────────────────────

  Future<void> _fetchUserLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      if (mounted) {
        setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  // Address listeners & autocomplete
  // ─────────────────────────────────────────────────────────

  void _onPickupChanged() {
    if (_settingPickup) return;
    if (_pickupLatLng != null) {
      setState(() => _pickupLatLng = null);
      _recalculate();
    }
    _schedulePickupAutocomplete();
  }

  void _onDeliveryChanged() {
    if (_settingDelivery) return;
    if (_deliveryLatLng != null) {
      setState(() => _deliveryLatLng = null);
      _recalculate();
    }
    _scheduleDeliveryAutocomplete();
  }

  void _schedulePickupAutocomplete() {
    _pickupDebounce?.cancel();
    final query = _pickupCtrl.text.trim();
    if (query.length < 3) {
      setState(() {
        _pickupSuggestions = [];
        _loadingPickupSuggestions = false;
      });
      return;
    }
    setState(() => _loadingPickupSuggestions = true);
    _pickupDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      final suggestions = await ref
          .read(geocodingServiceProvider)
          .autocomplete(query, focusPoint: _userLocation);
      if (!mounted) return;
      if (_pickupCtrl.text.trim() == query) {
        setState(() {
          _pickupSuggestions = suggestions;
          _loadingPickupSuggestions = false;
        });
      }
    });
  }

  void _scheduleDeliveryAutocomplete() {
    _deliveryDebounce?.cancel();
    final query = _deliveryCtrl.text.trim();
    if (query.length < 3) {
      setState(() {
        _deliverySuggestions = [];
        _loadingDeliverySuggestions = false;
      });
      return;
    }
    setState(() => _loadingDeliverySuggestions = true);
    _deliveryDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      final suggestions = await ref
          .read(geocodingServiceProvider)
          .autocomplete(query, focusPoint: _userLocation);
      if (!mounted) return;
      if (_deliveryCtrl.text.trim() == query) {
        setState(() {
          _deliverySuggestions = suggestions;
          _loadingDeliverySuggestions = false;
        });
      }
    });
  }

  void _selectPickup(AddressSuggestion s) {
    _pickupDebounce?.cancel();
    _settingPickup = true;
    _pickupCtrl.text = s.label;
    _settingPickup = false;
    _pickupFocus.unfocus();
    setState(() {
      _pickupLatLng = s.coordinates;
      _pickupSuggestions = [];
      _loadingPickupSuggestions = false;
    });
    _recalculate();
    if (_deliveryCtrl.text.trim().isEmpty) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) FocusScope.of(context).requestFocus(_deliveryFocus);
      });
    }
  }

  void _selectDelivery(AddressSuggestion s) {
    _deliveryDebounce?.cancel();
    _settingDelivery = true;
    _deliveryCtrl.text = s.label;
    _settingDelivery = false;
    _deliveryFocus.unfocus();
    setState(() {
      _deliveryLatLng = s.coordinates;
      _deliverySuggestions = [];
      _loadingDeliverySuggestions = false;
    });
    _recalculate();
  }

  Future<void> _useCurrentLocation() async {
    _pickupFocus.unfocus();
    setState(() => _loadingPickupSuggestions = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showSnack('Permissão de localização negada');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(position.latitude, position.longitude);
      final service = ref.read(geocodingServiceProvider);
      final address =
          await service.reverseGeocode(position.latitude, position.longitude);
      if (mounted) {
        _settingPickup = true;
        _pickupCtrl.text = address ?? 'Minha localização';
        _settingPickup = false;
        setState(() {
          _pickupLatLng = latLng;
          _pickupSuggestions = [];
        });
        _recalculate();
      }
    } catch (_) {
      _showSnack('Não foi possível obter sua localização');
    } finally {
      if (mounted) setState(() => _loadingPickupSuggestions = false);
    }
  }

  Future<bool> _ensureGeocoded() async {
    final service = ref.read(geocodingServiceProvider);
    if (_pickupLatLng == null && _pickupCtrl.text.trim().isNotEmpty) {
      final r = await service.geocode(_pickupCtrl.text.trim());
      if (r == null) {
        _showSnack(
            'Endereço de coleta não encontrado. Selecione uma sugestão.');
        return false;
      }
      _pickupLatLng = r;
    }
    if (_deliveryLatLng == null && _deliveryCtrl.text.trim().isNotEmpty) {
      final r = await service.geocode(_deliveryCtrl.text.trim());
      if (r == null) {
        _showSnack(
            'Endereço de entrega não encontrado. Selecione uma sugestão.');
        return false;
      }
      _deliveryLatLng = r;
    }
    return _pickupLatLng != null && _deliveryLatLng != null;
  }

  // ─────────────────────────────────────────────────────────
  // Price calculation
  // ─────────────────────────────────────────────────────────

  Future<void> _recalculate() async {
    if (_pickupLatLng == null ||
        _deliveryLatLng == null ||
        _selectedCategory == null) {
      setState(() {
        _distanceKm = null;
        _deliveryValue = null;
        _routePoints = [];
        _routeResult = null;
      });
      return;
    }

    _fitMapBounds();

    final from = _pickupLatLng!;
    final to = _deliveryLatLng!;

    try {
      // Usa a Rota Inteligente que resolve o valor minimo para não dar preju e os pontos da rua
      final result = await _routeService.getRouteWithInfo(from, to);
      
      if (!mounted) return;
      
      // Se os pontos não mudaram enquanto a requisição rodava:
      if (_pickupLatLng == from && _deliveryLatLng == to) {
        final realVal = PriceCalculator.calculate(_selectedCategory!, result.distanceKm);
        setState(() {
          _routePoints = result.points;
          _routeResult = result;
          _distanceKm = result.distanceKm;
          _deliveryValue = realVal;
        });
      }
    } catch (e) {
      debugPrint('Erro ao recalcular rota: $e');
    }
  }

  double _toRad(double deg) => deg * pi / 180;

  void _fitMapBounds() {
    if (_pickupLatLng == null || _deliveryLatLng == null) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(_pickupLatLng!, _deliveryLatLng!),
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  // Stepper navigation
  // ─────────────────────────────────────────────────────────

  void _nextStep() {
    if (_step == 0) {
      if (_selectedCategory == null) {
        _showSnack('Selecione o tipo de veículo');
        return;
      }
    } else if (_step == 1) {
      if (_pickupCtrl.text.trim().isEmpty ||
          _deliveryCtrl.text.trim().isEmpty) {
        _showSnack('Preencha os dois endereços');
        return;
      }
    }
    setState(() => _step++);
    if (_step == 2 && _pickupLatLng != null && _deliveryLatLng != null) {
      _recalculate();
    }
  }

  void _prevStep() {
    if (_step > 0) setState(() => _step--);
  }

  // ─────────────────────────────────────────────────────────
  // Submit
  // ─────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final ok = await _ensureGeocoded();
      if (!ok || !mounted) return;

      if (_deliveryValue == null) return;

      final user = ref.read(authNotifierProvider).valueOrNull;
      if (user == null) return;

      final delivery =
          await ref.read(deliveryRepositoryProvider).createDelivery(
                clientId: user.id,
                pickupAddress: _pickupCtrl.text.trim(),
                pickupLat: _pickupLatLng!.latitude,
                pickupLng: _pickupLatLng!.longitude,
                deliveryAddress: _deliveryCtrl.text.trim(),
                deliveryLat: _deliveryLatLng!.latitude,
                deliveryLng: _deliveryLatLng!.longitude,
                value: _deliveryValue!,
                paymentMethod: _paymentMethod,
                vehicleCategory:
                    _selectedCategory?.category ?? VehicleCategory.motoboy,
              );

      ref.invalidate(clientDeliveriesProvider);

      if (mounted) {
        context.go('/client/tracking/${delivery.id}');
      }
    } catch (e) {
      _showSnack('Erro ao criar entrega: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style:
              AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: _step > 0 ? _prevStep : () => context.pop(),
        ),
        title: Text('Nova Entrega', style: AppTypography.h3),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            // Stepper horizontal
            Padding(
              padding: AppSpacing.screenPadding,
              child: _StepperHeader(currentStep: _step),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Step content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: _buildStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildStepVehicle();
      case 1:
        return _buildStepAddresses();
      case 2:
        return _buildStepConfirm();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Etapa 1: Veículo ──────────────────────────────────────
  Widget _buildStepVehicle() {
    return SingleChildScrollView(
      key: const ValueKey('step_vehicle'),
      padding: AppSpacing.screenPaddingFull,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tipo de veículo', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Escolha o tamanho ideal para o seu pedido',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl2),
          CategorySelectorWidget(
            initialValue: _selectedCategory,
            onSelected: (cat) =>
                setState(() => _selectedCategory = cat),
          ),
          const SizedBox(height: AppSpacing.xl3),
          PrimaryButton(
            label: 'Continuar',
            onPressed: _selectedCategory == null ? null : _nextStep,
          ),
          const SizedBox(height: AppSpacing.xl2),
        ],
      ),
    );
  }

  // ── Etapa 2: Endereços ────────────────────────────────────
  Widget _buildStepAddresses() {
    return SingleChildScrollView(
      key: const ValueKey('step_addresses'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                _AddressField(
                  label: 'Coleta',
                  hint: 'Rua, número, bairro, cidade',
                  controller: _pickupCtrl,
                  focusNode: _pickupFocus,
                  isConfirmed: _pickupLatLng != null,
                  isLoading: _loadingPickupSuggestions,
                  suggestions: _pickupSuggestions,
                  onSuggestionTap: _selectPickup,
                  leadingIcon: Icons.radio_button_on_rounded,
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
                Padding(
                  padding: const EdgeInsets.only(left: 19, top: 4, bottom: 4),
                  child: Container(
                    width: 1,
                    height: 20,
                    color: AppColors.surfaceBorder,
                  ),
                ),
                _AddressField(
                  label: 'Entrega',
                  hint: 'Rua, número, bairro, cidade',
                  controller: _deliveryCtrl,
                  focusNode: _deliveryFocus,
                  isConfirmed: _deliveryLatLng != null,
                  isLoading: _loadingDeliverySuggestions,
                  suggestions: _deliverySuggestions,
                  onSuggestionTap: _selectDelivery,
                  leadingIcon: Icons.location_on_rounded,
                ),
                const SizedBox(height: AppSpacing.xl2),
              ],
            ),
          ),

          // Preview mapa
          if (_pickupLatLng != null || _deliveryLatLng != null)
            SizedBox(
              height: 200,
              child: _buildMapPreview(),
            ),

          Padding(
            padding: AppSpacing.screenPaddingFull,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl2),
                PrimaryButton(
                  label: 'Continuar',
                  onPressed: (_pickupCtrl.text.trim().isNotEmpty &&
                          _deliveryCtrl.text.trim().isNotEmpty)
                      ? () async {
                          final ok = await _ensureGeocoded();
                          if (ok) {
                            _recalculate();
                            _nextStep();
                          }
                        }
                      : null,
                ),
                const SizedBox(height: AppSpacing.xl2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Etapa 3: Confirmar ────────────────────────────────────
  Widget _buildStepConfirm() {
    return SingleChildScrollView(
      key: const ValueKey('step_confirm'),
      padding: AppSpacing.screenPaddingFull,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),

          // Preview de preço
          if (_deliveryValue != null && _distanceKm != null)
            PricePreviewCard(
              category: _selectedCategory!,
              distanceKm: _distanceKm!,
              totalValue: _deliveryValue!,
            ),
          const SizedBox(height: AppSpacing.xl2),

          // Pagamento
          Text('Pagamento', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _PaymentChip(
                icon: Icons.money_rounded,
                label: 'Dinheiro',
                value: 'cash',
                selected: _paymentMethod == 'cash',
                onTap: () => setState(() => _paymentMethod = 'cash'),
              ),
              const SizedBox(width: AppSpacing.sm),
              _PaymentChip(
                icon: Icons.pix_rounded,
                label: 'PIX',
                value: 'pix',
                selected: _paymentMethod == 'pix',
                onTap: () => setState(() => _paymentMethod = 'pix'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl3),

          // Endereços resumo
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
            ),
            child: Column(
              children: [
                _SummaryAddressRow(
                  icon: Icons.radio_button_on_rounded,
                  iconColor: AppColors.primary,
                  label: 'Coleta',
                  address: _pickupCtrl.text.trim(),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(color: AppColors.surfaceBorder, height: 1),
                const SizedBox(height: AppSpacing.sm),
                _SummaryAddressRow(
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.error,
                  label: 'Entrega',
                  address: _deliveryCtrl.text.trim(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl3),

          PrimaryButton(
            label: 'Confirmar Pedido',
            onPressed: _isLoading ? null : _submit,
            isLoading: _isLoading,
          ),
          const SizedBox(height: AppSpacing.xl2),
        ],
      ),
    );
  }

  Widget _buildMapPreview() {
    final center = _pickupLatLng ?? _deliveryLatLng!;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.mapTileUrl,
                userAgentPackageName: 'com.urbgo.app',
              ),
              MarkerLayer(
                markers: [
                  if (_pickupLatLng != null)
                    Marker(
                      point: _pickupLatLng!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.store_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  if (_deliveryLatLng != null)
                    Marker(
                      point: _deliveryLatLng!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.error.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.flag_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // Sombra da rota
                    Polyline(
                      points: _routePoints,
                      color: AppColors.primary.withValues(alpha: 0.15),
                      strokeWidth: 10,
                    ),
                    // Rota principal
                    Polyline(
                      points: _routePoints,
                      color: AppColors.primary,
                      strokeWidth: 4,
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Route info badges (top right)
        if (_routeResult != null)
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Distância
                _RouteInfoBadge(
                  icon: Icons.route_rounded,
                  label: _routeResult!.formattedDistance,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 6),
                // Tempo estimado
                _RouteInfoBadge(
                  icon: Icons.schedule_rounded,
                  label: _routeResult!.formattedDuration,
                  color: const Color(0xFF2196F3),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stepper Header
// ─────────────────────────────────────────────────────────────

class _StepperHeader extends StatelessWidget {
  final int currentStep;

  const _StepperHeader({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['Veículo', 'Endereços', 'Confirmar'];
    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          _StepDot(
            number: i + 1,
            label: labels[i],
            isActive: currentStep == i,
            isCompleted: currentStep > i,
          ),
          if (i < 2)
            Expanded(
              child: Container(
                height: 1,
                color: currentStep > i
                    ? AppColors.primary
                    : AppColors.surfaceBorder,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final int number;
  final String label;
  final bool isActive;
  final bool isCompleted;

  const _StepDot({
    required this.number,
    required this.label,
    required this.isActive,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final color = (isActive || isCompleted)
        ? AppColors.primary
        : AppColors.textTertiary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? AppColors.primary
                : isActive
                    ? AppColors.primaryDeep
                    : AppColors.surfaceHigh,
            border: Border.all(
              color: color,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check_rounded,
                    size: 14, color: AppColors.textInverse)
                : Text(
                    '$number',
                    style: AppTypography.labelSmall.copyWith(color: color),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Address Field with autocomplete
// ─────────────────────────────────────────────────────────────

class _AddressField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isConfirmed;
  final bool isLoading;
  final List<AddressSuggestion> suggestions;
  final void Function(AddressSuggestion) onSuggestionTap;
  final IconData leadingIcon;
  final Widget? suffixIcon;

  const _AddressField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.isConfirmed,
    required this.isLoading,
    required this.suggestions,
    required this.onSuggestionTap,
    required this.leadingIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          style:
              AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: _buildPrefixIcon(),
            suffixIcon: suffixIcon,
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: suggestions.isNotEmpty
              ? _SuggestionsCard(
                  key: ValueKey(suggestions.length),
                  suggestions: suggestions,
                  onTap: onSuggestionTap,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildPrefixIcon() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }
    return Icon(
      isConfirmed ? Icons.check_circle_rounded : leadingIcon,
      color: isConfirmed ? AppColors.primary : AppColors.textTertiary,
      size: 20,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Suggestions Card
// ─────────────────────────────────────────────────────────────

class _SuggestionsCard extends StatelessWidget {
  final List<AddressSuggestion> suggestions;
  final void Function(AddressSuggestion) onTap;

  const _SuggestionsCard({
    super.key,
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          color: AppColors.surfaceBorder,
          indent: 44,
        ),
        itemBuilder: (_, i) {
          final s = suggestions[i];
          return InkWell(
            onTap: () => onTap(s),
            borderRadius: i == 0
                ? const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.md),
                    topRight: Radius.circular(AppRadius.md),
                  )
                : i == suggestions.length - 1
                    ? const BorderRadius.only(
                        bottomLeft: Radius.circular(AppRadius.md),
                        bottomRight: Radius.circular(AppRadius.md),
                      )
                    : BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      color: AppColors.textTertiary, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      s.label,
                      style: AppTypography.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Payment Chip
// ─────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
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

// ─────────────────────────────────────────────────────────────
// Summary Address Row (step 3)
// ─────────────────────────────────────────────────────────────

class _SummaryAddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  const _SummaryAddressRow({
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
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary),
              ),
              Text(
                address,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
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

// ─────────────────────────────────────────────────────────────
// Route Info Badge (distance / time on map)
// ─────────────────────────────────────────────────────────────

class _RouteInfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RouteInfoBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
