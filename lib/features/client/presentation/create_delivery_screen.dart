import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/dynamic_pricing_service.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/services/route_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/category_selector.dart';
import '../../shared/widgets/price_preview_card.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/client_providers.dart';

class CreateDeliveryScreen extends ConsumerStatefulWidget {
  final VehicleCategoryInfo? initialCategory;

  const CreateDeliveryScreen({super.key, this.initialCategory});

  @override
  ConsumerState<CreateDeliveryScreen> createState() =>
      _CreateDeliveryScreenState();
}

class _CreateDeliveryScreenState extends ConsumerState<CreateDeliveryScreen> {
  // ── Endereços ─────────────────────────────────────────────
  final _pickupCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  final _mapController = MapController();
  final _pickupFocus = FocusNode();
  final _deliveryFocus = FocusNode();
  final _extraStopCtrl = TextEditingController();
  final _extraStopFocus = FocusNode();

  // ── Detalhes ──────────────────────────────────────────────
  final _recipientNameCtrl = TextEditingController();
  final _recipientPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _declaredValueCtrl = TextEditingController();

  // ── Stepper ──────────────────────────────────────────────
  int _step = 0;

  // ── Categoria ─────────────────────────────────────────────
  VehicleCategoryInfo? _selectedCategory;
  bool get _isMotoTaxi =>
      _selectedCategory?.category == VehicleCategory.mototaxi;

  // ── Endereços state ───────────────────────────────────────
  LatLng? _pickupLatLng;
  LatLng? _deliveryLatLng;
  double? _distanceKm;
  double? _deliveryValue;
  String _paymentMethod = 'pix';
  bool _isLoading = false;

  List<AddressSuggestion> _pickupSuggestions = [];
  List<AddressSuggestion> _deliverySuggestions = [];
  bool _loadingPickupSuggestions = false;
  bool _loadingDeliverySuggestions = false;
  Timer? _pickupDebounce;
  Timer? _deliveryDebounce;
  bool _settingPickup = false;
  bool _settingDelivery = false;

  LatLng? _extraStopLatLng;
  List<AddressSuggestion> _extraStopSuggestions = [];
  bool _loadingExtraStopSuggestions = false;
  Timer? _extraStopDebounce;
  bool _hasExtraStop = false;
  bool _settingExtraStop = false;

  final RouteService _routeService = RouteService();
  List<LatLng> _routePoints = [];
  RouteResult? _routeResult;
  LatLng? _userLocation;
  SurgeInfo? _surgeInfo;

  // ── Detalhes state ─────────────────────────────────────────
  bool _isFragile = false;
  int _helperCount = 0;
  bool _roundTrip = false;
  String? _cargoType;
  DateTime? _scheduledFor;
  bool _helmetAcknowledged = false;

  // ── Stepper labels ─────────────────────────────────────────
  List<String> get _stepLabels => _isMotoTaxi
      ? ['Veículo', 'Rota', 'Segurança', 'Confirmar']
      : ['Veículo', 'Endereços', 'Detalhes', 'Confirmar'];

  bool get _canProceedFromDetails {
    if (_isMotoTaxi) return _helmetAcknowledged;
    final nameOk = _recipientNameCtrl.text.trim().isNotEmpty;
    final phoneOk = _recipientPhoneCtrl.text.trim().length >= 10;
    return nameOk && phoneOk;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory;
      _step = 1;
    }
    _fetchUserLocation();
    _loadSurgeInfo();
    _pickupCtrl.addListener(_onPickupChanged);
    _deliveryCtrl.addListener(_onDeliveryChanged);
    _extraStopCtrl.addListener(_onExtraStopChanged);
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
    _extraStopFocus.addListener(() {
      if (!_extraStopFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _extraStopSuggestions = []);
        });
      }
    });
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _deliveryCtrl.dispose();
    _extraStopCtrl.dispose();
    _mapController.dispose();
    _pickupFocus.dispose();
    _deliveryFocus.dispose();
    _extraStopFocus.dispose();
    _pickupDebounce?.cancel();
    _deliveryDebounce?.cancel();
    _extraStopDebounce?.cancel();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _declaredValueCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // Location
  // ─────────────────────────────────────────────────────────

  Future<void> _loadSurgeInfo() async {
    final surge = await DynamicPricingService().getCurrentSurge();
    if (mounted) {
      setState(() => _surgeInfo = surge);
      if (_pickupLatLng != null && _deliveryLatLng != null) {
        _recalculate();
      }
    }
  }

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
  // Autocomplete
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

  void _onExtraStopChanged() {
    if (_settingExtraStop) return;
    if (_extraStopLatLng != null) setState(() => _extraStopLatLng = null);
    _scheduleExtraStopAutocomplete();
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

  void _scheduleExtraStopAutocomplete() {
    _extraStopDebounce?.cancel();
    final query = _extraStopCtrl.text.trim();
    if (query.length < 3) {
      setState(() {
        _extraStopSuggestions = [];
        _loadingExtraStopSuggestions = false;
      });
      return;
    }
    setState(() => _loadingExtraStopSuggestions = true);
    _extraStopDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      final suggestions = await ref
          .read(geocodingServiceProvider)
          .autocomplete(query, focusPoint: _userLocation);
      if (!mounted) return;
      if (_extraStopCtrl.text.trim() == query) {
        setState(() {
          _extraStopSuggestions = suggestions;
          _loadingExtraStopSuggestions = false;
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

  void _selectExtraStop(AddressSuggestion s) {
    _extraStopDebounce?.cancel();
    _settingExtraStop = true;
    _extraStopCtrl.text = s.label;
    _settingExtraStop = false;
    _extraStopFocus.unfocus();
    setState(() {
      _extraStopLatLng = s.coordinates;
      _extraStopSuggestions = [];
      _loadingExtraStopSuggestions = false;
    });
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
      final address = await service.reverseGeocode(
        position.latitude,
        position.longitude,
      );
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
        _showSnack('Endereço de coleta não encontrado. Selecione uma sugestão.');
        return false;
      }
      _pickupLatLng = r;
    }
    if (_deliveryLatLng == null && _deliveryCtrl.text.trim().isNotEmpty) {
      final r = await service.geocode(_deliveryCtrl.text.trim());
      if (r == null) {
        _showSnack('Endereço de entrega não encontrado. Selecione uma sugestão.');
        return false;
      }
      _deliveryLatLng = r;
    }
    if (_hasExtraStop &&
        _extraStopLatLng == null &&
        _extraStopCtrl.text.trim().isNotEmpty) {
      final r = await service.geocode(_extraStopCtrl.text.trim());
      if (r == null) {
        _showSnack('Parada extra não encontrada. Selecione uma sugestão válida.');
        return false;
      }
      _extraStopLatLng = r;
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

    final from = _pickupLatLng!;
    final to = _deliveryLatLng!;
    final expectedExtraStop =
        _hasExtraStop && _extraStopLatLng != null ? _extraStopLatLng : null;
    final stops = [from, if (expectedExtraStop != null) expectedExtraStop, to];

    _fitMapBounds();

    try {
      final result = await _routeService.getRouteWithStops(stops);
      if (!mounted) return;

      final sameExtraStop =
          (_extraStopLatLng == null && expectedExtraStop == null) ||
          _extraStopLatLng == expectedExtraStop;
      if (_pickupLatLng == from && _deliveryLatLng == to && sameExtraStop) {
        final multiplier = _surgeInfo?.multiplier ?? 1.0;
        final realVal = PriceCalculator.calculate(
          _selectedCategory!,
          result.distanceKm,
          surgeMultiplier: multiplier,
        );
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

  void _fitMapBounds() {
    if (_pickupLatLng == null || _deliveryLatLng == null) return;
    try {
      final points = <LatLng>[
        _pickupLatLng!,
        if (_hasExtraStop && _extraStopLatLng != null) _extraStopLatLng!,
        _deliveryLatLng!,
      ];
      if (points.length == 1 || points.toSet().length == 1) {
        _mapController.move(points.first, 16);
        return;
      }
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
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
      if (_pickupCtrl.text.trim().isEmpty || _deliveryCtrl.text.trim().isEmpty) {
        _showSnack('Preencha os dois endereços');
        return;
      }
    } else if (_step == 2) {
      if (!_canProceedFromDetails) {
        if (_isMotoTaxi) {
          _showSnack('Confirme o uso de capacete para continuar');
        } else {
          _showSnack('Preencha o nome e telefone do destinatário');
        }
        return;
      }
    }
    setState(() => _step++);
    if (_step == 3 && _pickupLatLng != null && _deliveryLatLng != null) {
      _recalculate();
    }
  }

  void _prevStep() {
    if (_step > 0) setState(() => _step--);
  }

  // ─────────────────────────────────────────────────────────
  // Scheduling
  // ─────────────────────────────────────────────────────────

  Future<void> _pickScheduledTime() async {
    final now = DateTime.now();
    final minDate = now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: minDate,
      firstDate: minDate,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.textInverse,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minDate.hour, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.textInverse,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  // ─────────────────────────────────────────────────────────
  // Submit
  // ─────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final connected = await ConnectivityService.ensureConnected(
      context,
      message: 'Conecte-se à internet para criar a entrega.',
    );
    if (!connected || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final ok = await _ensureGeocoded();
      if (!ok || !mounted) return;
      if (_deliveryValue == null || _distanceKm == null) return;

      final user = ref.read(authNotifierProvider).valueOrNull;
      if (user == null) return;

      final declaredValue = _declaredValueCtrl.text.trim().isNotEmpty
          ? double.tryParse(
              _declaredValueCtrl.text.trim().replaceAll(',', '.'),
            )
          : null;

      final totalValue = _deliveryValue! +
          PriceCalculator.helperFee(_helperCount);

      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .createDelivery(
            clientId: user.id,
            pickupAddress: _pickupCtrl.text.trim(),
            pickupLat: _pickupLatLng!.latitude,
            pickupLng: _pickupLatLng!.longitude,
            deliveryAddress: _deliveryCtrl.text.trim(),
            deliveryLat: _deliveryLatLng!.latitude,
            deliveryLng: _deliveryLatLng!.longitude,
            value: totalValue,
            paymentMethod: _paymentMethod,
            distanceKm: _distanceKm!,
            vehicleCategory:
                _selectedCategory?.category ?? VehicleCategory.motoboy,
            extraStopAddress:
                (_hasExtraStop && _extraStopCtrl.text.trim().isNotEmpty)
                ? _extraStopCtrl.text.trim()
                : null,
            extraStopLat: _extraStopLatLng?.latitude,
            extraStopLng: _extraStopLatLng?.longitude,
            recipientName: _isMotoTaxi
                ? null
                : _recipientNameCtrl.text.trim().isNotEmpty
                    ? _recipientNameCtrl.text.trim()
                    : null,
            recipientPhone: _isMotoTaxi
                ? null
                : _recipientPhoneCtrl.text.trim().isNotEmpty
                    ? _recipientPhoneCtrl.text.trim()
                    : null,
            itemDescription: _notesCtrl.text.trim().isNotEmpty
                ? _notesCtrl.text.trim()
                : null,
            isFragile: _isFragile,
            declaredValue: declaredValue,
            helperCount: _helperCount,
            roundTrip: _roundTrip,
            scheduledFor: _scheduledFor,
            cargoType: _cargoType,
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
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
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
    final appBarTitle =
        _isMotoTaxi ? 'Nova Corrida' : 'Nova Entrega';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: _step > 0 ? _prevStep : () => context.pop(),
        ),
        title: Text(appBarTitle, style: AppTypography.h3),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.screenPadding,
              child: _StepperHeader(
                currentStep: _step,
                labels: _stepLabels,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
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
        return _isMotoTaxi ? _buildStepSafety() : _buildStepDetails();
      case 3:
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
            onSelected: (cat) => setState(() => _selectedCategory = cat),
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

  // ── Etapa 2: Endereços / Rota ─────────────────────────────

  Widget _buildStepAddresses() {
    final isMotoTaxi = _isMotoTaxi;
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

                // Aviso bike distância
                if (_selectedCategory?.category == VehicleCategory.bike &&
                    _distanceKm != null &&
                    _distanceKm! > 3)
                  _BikeDistanceWarning(distanceKm: _distanceKm!),

                _AddressField(
                  label: isMotoTaxi ? 'Origem' : 'Coleta',
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
                  label: isMotoTaxi ? 'Destino' : 'Entrega',
                  hint: 'Rua, número, bairro, cidade',
                  controller: _deliveryCtrl,
                  focusNode: _deliveryFocus,
                  isConfirmed: _deliveryLatLng != null,
                  isLoading: _loadingDeliverySuggestions,
                  suggestions: _deliverySuggestions,
                  onSuggestionTap: _selectDelivery,
                  leadingIcon: Icons.location_on_rounded,
                ),

                // Parada extra (não para MotoTaxi)
                if (!isMotoTaxi) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ExtraStopSection(
                    enabled: _hasExtraStop,
                    controller: _extraStopCtrl,
                    focusNode: _extraStopFocus,
                    isConfirmed: _extraStopLatLng != null,
                    isLoading: _loadingExtraStopSuggestions,
                    suggestions: _extraStopSuggestions,
                    onToggle: (enabled) {
                      setState(() {
                        _hasExtraStop = enabled;
                        if (!enabled) {
                          _extraStopCtrl.clear();
                          _extraStopLatLng = null;
                          _extraStopSuggestions = [];
                          _loadingExtraStopSuggestions = false;
                        }
                      });
                      _recalculate();
                    },
                    onSuggestionTap: (suggestion) {
                      _selectExtraStop(suggestion);
                      _recalculate();
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.xl2),
              ],
            ),
          ),

          if (_pickupLatLng != null || _deliveryLatLng != null)
            SizedBox(height: 200, child: _buildMapPreview()),

          Padding(
            padding: AppSpacing.screenPaddingFull,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl2),
                PrimaryButton(
                  label: 'Continuar',
                  onPressed:
                      (_pickupCtrl.text.trim().isNotEmpty &&
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

  // ── Etapa 3a: Detalhes da entrega ─────────────────────────

  Widget _buildStepDetails() {
    final cat = _selectedCategory?.category;
    final isVan = cat == VehicleCategory.van;
    final isTruck = cat == VehicleCategory.truck;
    final isBike = cat == VehicleCategory.bike;
    final needsHelper = isVan || isTruck;
    final maxHelpers = isTruck ? 3 : 2;

    return SingleChildScrollView(
      key: const ValueKey('step_details'),
      padding: AppSpacing.screenPaddingFull,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aviso bike distância
          if (isBike && _distanceKm != null && _distanceKm! > 3)
            _BikeDistanceWarning(distanceKm: _distanceKm!),

          // ── Destinatário ────────────────────────────────
          Text('Destinatário', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Quem vai receber a entrega?',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),

          _FormField(
            label: 'Nome do destinatário',
            hint: 'Ex: João Silva',
            controller: _recipientNameCtrl,
            icon: Icons.person_rounded,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            required: true,
          ),
          const SizedBox(height: AppSpacing.md),
          _FormField(
            label: 'Telefone do destinatário',
            hint: '(11) 99999-9999',
            controller: _recipientPhoneCtrl,
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            required: true,
          ),
          const SizedBox(height: AppSpacing.xl2),

          // ── Tipo de carga (Van/Truck) ────────────────────
          if (needsHelper) ...[
            Text('Tipo de carga', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.md),
            _CargoTypeSelector(
              selected: _cargoType,
              onSelected: (type) => setState(() => _cargoType = type),
            ),
            const SizedBox(height: AppSpacing.xl2),

            // ── Ajudante ────────────────────────────────────
            _HelperSelector(
              count: _helperCount,
              maxHelpers: maxHelpers,
              onChanged: (c) => setState(() => _helperCount = c),
            ),
            const SizedBox(height: AppSpacing.xl2),
          ],

          // ── Opções adicionais ───────────────────────────
          Text('Opções', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.md),

          // Round trip (Carro e Van)
          if (cat == VehicleCategory.car || isVan) ...[
            _ToggleOption(
              icon: Icons.repeat_rounded,
              label: 'Ida e volta',
              description: 'O veículo retorna ao ponto de coleta após entregar',
              value: _roundTrip,
              onChanged: (v) => setState(() => _roundTrip = v),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Frágil (não para van/truck — eles têm helpers)
          if (!needsHelper)
            _ToggleOption(
              icon: Icons.warning_amber_rounded,
              label: 'Item frágil',
              description: 'Avisar o entregador para manusear com cuidado',
              value: _isFragile,
              onChanged: (v) => setState(() => _isFragile = v),
              activeColor: const Color(0xFFFF9800),
            ),

          const SizedBox(height: AppSpacing.xl2),

          // ── Observações ─────────────────────────────────
          Text('Observações', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Instruções para o entregador (portão, bloco, referência...)',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 3,
            maxLength: 300,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              hintText: 'Ex: Portão azul, apartamento 302, interfone 0302...',
              counterStyle: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpacing.xl2),

          // ── Valor declarado ─────────────────────────────
          _DeclaredValueSection(
            controller: _declaredValueCtrl,
          ),
          const SizedBox(height: AppSpacing.xl2),

          // ── Agendamento (Van/Truck) ──────────────────────
          if (needsHelper) ...[
            _SchedulingSection(
              scheduledFor: _scheduledFor,
              onTap: _pickScheduledTime,
              onClear: () => setState(() => _scheduledFor = null),
            ),
            const SizedBox(height: AppSpacing.xl2),
          ],

          PrimaryButton(
            label: 'Continuar',
            onPressed: _canProceedFromDetails ? _nextStep : null,
          ),
          const SizedBox(height: AppSpacing.xl2),
        ],
      ),
    );
  }

  // ── Etapa 3b: Segurança (MotoTáxi) ───────────────────────

  Widget _buildStepSafety() {
    return SingleChildScrollView(
      key: const ValueKey('step_safety'),
      padding: AppSpacing.screenPaddingFull,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card capacete
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: const Color(0xFFFF9800).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sports_motorsports_rounded,
                    color: Color(0xFFFF9800),
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Use o capacete sempre',
                        style: AppTypography.labelLarge.copyWith(
                          color: const Color(0xFFFF9800),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'O uso de capacete é obrigatório por lei (Art. 244, CTB). O motorista é obrigado a fornecer ou garantir que você use um.',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Card seguro
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
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
                        'Sua segurança em primeiro lugar',
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Durante a corrida você terá acesso ao botão de emergência SOS na tela de rastreamento.',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Card dicas
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dicas de segurança', style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.md),
                const _SafetyTip(
                  icon: Icons.health_and_safety_rounded,
                  text: 'Certifique-se de usar capacete homologado',
                ),
                const SizedBox(height: AppSpacing.sm),
                const _SafetyTip(
                  icon: Icons.share_location_rounded,
                  text: 'Você pode compartilhar sua rota durante a corrida',
                ),
                const SizedBox(height: AppSpacing.sm),
                const _SafetyTip(
                  icon: Icons.emergency_rounded,
                  text: 'O botão SOS estará sempre visível no tracking',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl2),

          // Confirmação de capacete
          GestureDetector(
            onTap: () =>
                setState(() => _helmetAcknowledged = !_helmetAcknowledged),
            child: Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: _helmetAcknowledged
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: _helmetAcknowledged
                      ? AppColors.primary
                      : AppColors.surfaceBorder,
                  width: _helmetAcknowledged ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _helmetAcknowledged
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _helmetAcknowledged
                            ? AppColors.primary
                            : AppColors.textTertiary,
                        width: 1.5,
                      ),
                    ),
                    child: _helmetAcknowledged
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: AppColors.textInverse,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Estou ciente do uso obrigatório de capacete e das regras de segurança',
                      style: AppTypography.bodyMedium.copyWith(
                        color: _helmetAcknowledged
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl3),

          PrimaryButton(
            label: 'Buscar motorista',
            onPressed: _helmetAcknowledged ? _nextStep : null,
          ),
          const SizedBox(height: AppSpacing.xl2),
        ],
      ),
    );
  }

  // ── Etapa 4: Confirmar ────────────────────────────────────

  Widget _buildStepConfirm() {
    final isMotoTaxi = _isMotoTaxi;
    final helperFee = PriceCalculator.helperFee(_helperCount);
    final totalValue = (_deliveryValue ?? 0) + helperFee;

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
              totalValue: totalValue,
              surgeInfo: _surgeInfo,
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

          // Resumo de endereços
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  icon: Icons.radio_button_on_rounded,
                  iconColor: AppColors.primary,
                  label: isMotoTaxi ? 'Origem' : 'Coleta',
                  value: _pickupCtrl.text.trim(),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(color: AppColors.surfaceBorder, height: 1),
                const SizedBox(height: AppSpacing.sm),
                _SummaryRow(
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.error,
                  label: isMotoTaxi ? 'Destino' : 'Entrega',
                  value: _deliveryCtrl.text.trim(),
                ),
                if (_hasExtraStop && _extraStopCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(color: AppColors.surfaceBorder, height: 1),
                  const SizedBox(height: AppSpacing.sm),
                  _SummaryRow(
                    icon: Icons.add_location_alt_rounded,
                    iconColor: const Color(0xFFFF9800),
                    label: 'Parada extra',
                    value: _extraStopCtrl.text.trim(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Resumo detalhes
          if (!isMotoTaxi) ...[
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
              ),
              child: Column(
                children: [
                  if (_recipientNameCtrl.text.trim().isNotEmpty)
                    _SummaryRow(
                      icon: Icons.person_rounded,
                      iconColor: AppColors.textSecondary,
                      label: 'Destinatário',
                      value: _recipientNameCtrl.text.trim(),
                    ),
                  if (_recipientPhoneCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    _SummaryRow(
                      icon: Icons.phone_rounded,
                      iconColor: AppColors.textSecondary,
                      label: 'Telefone',
                      value: _recipientPhoneCtrl.text.trim(),
                    ),
                  ],
                  if (_cargoType != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    _SummaryRow(
                      icon: Icons.inventory_2_rounded,
                      iconColor: AppColors.textSecondary,
                      label: 'Tipo de carga',
                      value: _cargoTypeLabel(_cargoType),
                    ),
                  ],
                  if (_helperCount > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    _SummaryRow(
                      icon: Icons.people_rounded,
                      iconColor: const Color(0xFFFF9800),
                      label: 'Ajudantes',
                      value: '$_helperCount ajudante${_helperCount > 1 ? 's' : ''} (+R\$ ${helperFee.toStringAsFixed(0)})',
                    ),
                  ],
                  if (_isFragile) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    const _SummaryRow(
                      icon: Icons.warning_amber_rounded,
                      iconColor: Color(0xFFFF9800),
                      label: 'Atenção',
                      value: 'Item frágil',
                    ),
                  ],
                  if (_roundTrip) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    const _SummaryRow(
                      icon: Icons.repeat_rounded,
                      iconColor: AppColors.primary,
                      label: 'Trajeto',
                      value: 'Ida e volta',
                    ),
                  ],
                  if (_scheduledFor != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    _SummaryRow(
                      icon: Icons.event_rounded,
                      iconColor: AppColors.primary,
                      label: 'Agendamento',
                      value: _scheduledForLabel(_scheduledFor!),
                    ),
                  ],
                  if (_notesCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    _SummaryRow(
                      icon: Icons.notes_rounded,
                      iconColor: AppColors.textSecondary,
                      label: 'Obs.',
                      value: _notesCtrl.text.trim(),
                      maxLines: 3,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          PrimaryButton(
            label: isMotoTaxi ? 'Confirmar Corrida' : 'Confirmar Pedido',
            onPressed: _isLoading ? null : _submit,
            isLoading: _isLoading,
          ),
          const SizedBox(height: AppSpacing.xl2),
        ],
      ),
    );
  }

  String _cargoTypeLabel(String? type) => switch (type) {
    'furniture' => 'Móveis',
    'appliances' => 'Eletrodomésticos',
    'construction' => 'Material de obra',
    'other' => 'Outros',
    _ => 'Geral',
  };

  String _scheduledForLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'Hoje às $timeStr';
    final tomorrow = today.add(const Duration(days: 1));
    if (day == tomorrow) return 'Amanhã às $timeStr';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às $timeStr';
  }

  // ── Mapa preview ──────────────────────────────────────────

  Widget _buildMapPreview() {
    final center = _pickupLatLng ?? _deliveryLatLng!;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 13),
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
                          Icons.radio_button_on_rounded,
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
                  if (_hasExtraStop && _extraStopLatLng != null)
                    Marker(
                      point: _extraStopLatLng!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF9800).withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_location_alt_rounded,
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
                    Polyline(
                      points: _routePoints,
                      color: AppColors.primary.withValues(alpha: 0.15),
                      strokeWidth: 10,
                    ),
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
        if (_routeResult != null)
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _RouteInfoBadge(
                  icon: Icons.route_rounded,
                  label: _routeResult!.formattedDistance,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 6),
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
// Stepper Header (agora 4 steps)
// ─────────────────────────────────────────────────────────────

class _StepperHeader extends StatelessWidget {
  final int currentStep;
  final List<String> labels;

  const _StepperHeader({required this.currentStep, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < labels.length; i++) ...[
          _StepDot(
            number: i + 1,
            label: labels[i],
            isActive: currentStep == i,
            isCompleted: currentStep > i,
          ),
          if (i < labels.length - 1)
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
    final color =
        (isActive || isCompleted) ? AppColors.primary : AppColors.textTertiary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? AppColors.primary
                : isActive
                ? AppColors.primaryDeep
                : AppColors.surfaceHigh,
            border: Border.all(color: color, width: isActive ? 2 : 1),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: AppColors.textInverse,
                  )
                : Text(
                    '$number',
                    style: AppTypography.labelSmall.copyWith(
                      color: color,
                      fontSize: 11,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Address Field
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
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
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
// Extra Stop Section
// ─────────────────────────────────────────────────────────────

class _ExtraStopSection extends StatelessWidget {
  final bool enabled;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isConfirmed;
  final bool isLoading;
  final List<AddressSuggestion> suggestions;
  final ValueChanged<bool> onToggle;
  final void Function(AddressSuggestion) onSuggestionTap;

  const _ExtraStopSection({
    required this.enabled,
    required this.controller,
    required this.focusNode,
    required this.isConfirmed,
    required this.isLoading,
    required this.suggestions,
    required this.onToggle,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.alt_route_rounded,
                color: Color(0xFFFF9800),
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Adicionar parada extra',
                  style: AppTypography.labelLarge,
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.35),
                activeThumbColor: AppColors.primary,
                onChanged: onToggle,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Use quando a rota precisar passar por um endereço intermediário.',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            _AddressField(
              label: 'Parada extra',
              hint: 'Rua, número, bairro, cidade',
              controller: controller,
              focusNode: focusNode,
              isConfirmed: isConfirmed,
              isLoading: isLoading,
              suggestions: suggestions,
              onSuggestionTap: onSuggestionTap,
              leadingIcon: Icons.add_location_alt_rounded,
            ),
          ],
        ],
      ),
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
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
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
// Form Field
// ─────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool required;

  const _FormField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppTypography.labelLarge),
            if (required) ...[
              const SizedBox(width: 4),
              Text(
                '*',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Cargo Type Selector
// ─────────────────────────────────────────────────────────────

class _CargoTypeSelector extends StatelessWidget {
  final String? selected;
  final void Function(String) onSelected;

  const _CargoTypeSelector({
    required this.selected,
    required this.onSelected,
  });

  static const _types = [
    ('furniture', Icons.weekend_rounded, 'Móveis'),
    ('appliances', Icons.kitchen_rounded, 'Eletrodomésticos'),
    ('construction', Icons.construction_rounded, 'Material de obra'),
    ('other', Icons.category_rounded, 'Outros'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: _types.map((t) {
        final (id, icon, label) = t;
        final isSelected = selected == id;
        return GestureDetector(
          onTap: () => onSelected(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.surfaceBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helper Selector
// ─────────────────────────────────────────────────────────────

class _HelperSelector extends StatelessWidget {
  final int count;
  final int maxHelpers;
  final void Function(int) onChanged;

  const _HelperSelector({
    required this.count,
    required this.maxHelpers,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.people_rounded,
                color: Color(0xFFFF9800),
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Ajudante para carga/descarga', style: AppTypography.labelLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Necessário para móveis, eletrodomésticos pesados e mudanças',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (int i = 0; i <= maxHelpers; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                _HelperOption(
                  value: i,
                  selected: count == i,
                  onTap: () => onChanged(i),
                ),
              ],
            ],
          ),
          if (count > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    size: 14,
                    color: Color(0xFFFF9800),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '+R\$ ${(count * 15).toStringAsFixed(0)} por ajudante',
                    style: AppTypography.labelSmall.copyWith(
                      color: const Color(0xFFFF9800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HelperOption extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _HelperOption({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 44,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF9800).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF9800)
                : AppColors.surfaceBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value == 0 ? 'Sem' : '$value',
              style: AppTypography.labelLarge.copyWith(
                color: selected
                    ? const Color(0xFFFF9800)
                    : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            if (value > 0)
              Text(
                value == 1 ? 'ajudante' : 'ajudantes',
                style: AppTypography.bodySmall.copyWith(fontSize: 8),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Toggle Option
// ─────────────────────────────────────────────────────────────

class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;

  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.primary;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.07) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: value ? color.withValues(alpha: 0.4) : AppColors.surfaceBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: value ? color : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelLarge.copyWith(
                      color: value ? color : AppColors.textPrimary,
                    ),
                  ),
                  Text(description, style: AppTypography.bodySmall),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeTrackColor: color.withValues(alpha: 0.35),
              activeThumbColor: color,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Declared Value Section
// ─────────────────────────────────────────────────────────────

class _DeclaredValueSection extends StatelessWidget {
  final TextEditingController controller;

  const _DeclaredValueSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Valor declarado', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Opcional. Informe o valor do item para fins de seguro pessoal.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(10),
          ],
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Ex: 150,00',
            prefixIcon: Icon(
              Icons.attach_money_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
            prefixText: 'R\$ ',
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Scheduling Section
// ─────────────────────────────────────────────────────────────

class _SchedulingSection extends StatelessWidget {
  final DateTime? scheduledFor;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _SchedulingSection({
    required this.scheduledFor,
    required this.onTap,
    required this.onClear,
  });

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'Hoje às $timeStr';
    final tomorrow = today.add(const Duration(days: 1));
    if (day == tomorrow) return 'Amanhã às $timeStr';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: scheduledFor != null
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: scheduledFor != null
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.surfaceBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_rounded,
              size: 20,
              color: scheduledFor != null
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agendar para depois',
                    style: AppTypography.labelLarge.copyWith(
                      color: scheduledFor != null
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    scheduledFor != null
                        ? _formatDate(scheduledFor!)
                        : 'Toque para escolher data e hora',
                    style: AppTypography.bodySmall.copyWith(
                      color: scheduledFor != null
                          ? AppColors.primary
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (scheduledFor != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bike Distance Warning
// ─────────────────────────────────────────────────────────────

class _BikeDistanceWarning extends StatelessWidget {
  final double distanceKm;

  const _BikeDistanceWarning({required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFF9800),
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Bike ideal para até 3 km. Sua rota tem ${distanceKm.toStringAsFixed(1)} km — a entrega pode demorar mais.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Safety Tip
// ─────────────────────────────────────────────────────────────

class _SafetyTip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SafetyTip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: AppTypography.bodySmall),
        ),
      ],
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
                  color: selected ? AppColors.primary : AppColors.textSecondary,
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
// Summary Row (confirm step)
// ─────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final int maxLines;

  const _SummaryRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.maxLines = 2,
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
                ),
              ),
              Text(
                value,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                maxLines: maxLines,
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
// Route Info Badge
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
