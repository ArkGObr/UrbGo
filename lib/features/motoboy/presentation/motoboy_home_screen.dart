import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_toast.dart';
import '../../auth/domain/auth_provider.dart';
import '../../client/domain/delivery_model.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/driver_registration_rules.dart';
import '../domain/motoboy_model.dart';
import '../domain/motoboy_providers.dart';

// Centro padrão: São Paulo
const _kDefaultCenter = LatLng(-23.5505, -46.6333);

class MotoboyHomeScreen extends ConsumerStatefulWidget {
  const MotoboyHomeScreen({super.key});

  @override
  ConsumerState<MotoboyHomeScreen> createState() => _MotoboyHomeScreenState();
}

class _MotoboyHomeScreenState extends ConsumerState<MotoboyHomeScreen>
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _mapController = MapController();

  bool _isToggling = false;
  LatLng? _currentPosition;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<Position>? _positionSub;
  RealtimeChannel? _runsChannel;
  bool _isShowingModal = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulseAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _initPosition();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkActiveDelivery());
  }

  /// Se o motoboy fechou o app com uma corrida ativa, redireciona ao abrir
  Future<void> _checkActiveDelivery() async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null || !user.isMotoboy) return;

    try {
      final data = await Supabase.instance.client
          .from('deliveries')
          .select()
          .eq('motoboy_id', user.id)
          .inFilter('status', ['accepted', 'in_progress'])
          .limit(1);

      if ((data as List).isNotEmpty && mounted) {
        final delivery = DeliveryModel.fromJson(data.first);
        context.go('/motoboy/active/${delivery.id}');
      }
    } catch (_) {
      // Silencia — não crítico
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _positionSub?.cancel();
    _runsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _initPosition() async {
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
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentPosition = latLng);
      _mapController.move(latLng, 15);

      // Cancela stream anterior antes de criar um novo
      await _positionSub?.cancel();
      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen((p) {
            if (!mounted) return;
            setState(() => _currentPosition = LatLng(p.latitude, p.longitude));
          });
    } catch (_) {
      // Fallback: tenta sem timeLimit
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null && mounted) {
          final latLng = LatLng(pos.latitude, pos.longitude);
          setState(() => _currentPosition = latLng);
          _mapController.move(latLng, 15);
        }
      } catch (_) {}
    }
  }

  Future<bool> _requestLocationPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  Future<void> _toggleOnline(bool currentlyOnline) async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null) return;

    final connected = await ConnectivityService.ensureConnected(
      context,
      message: currentlyOnline
          ? 'Conecte-se para atualizar seu status.'
          : 'Conecte-se para entrar online e receber corridas.',
    );
    if (!connected || !mounted) return;

    setState(() => _isToggling = true);

    try {
      final repo = ref.read(motoboyRepositoryProvider);

      if (!currentlyOnline) {
        final hasPermission = await _requestLocationPermission();
        if (!hasPermission) {
          if (mounted) {
            AppToast.show(
              context,
              title: 'Localização necessária',
              subtitle: 'Ative a permissão de localização para ficar online',
              type: AppToastType.warning,
            );
          }
          return;
        }
        await repo.setOnline(user.id, true);
        repo.startLocationUpdates(user.id);

        _runsChannel ??= repo.watchAvailableRuns(() async {
          if (!mounted) return;
          // Invalida e força atualização do provider
          ref.invalidate(availableRunsProvider);
          try {
            final runs = await ref.read(availableRunsProvider.future);
            if (runs.isNotEmpty && mounted && !_isShowingModal) {
              _showScandalousNewRunModal(runs.first.value);
            }
          } catch (_) {}
        });

        await _initPosition();
        if (mounted) {
          AppToast.show(
            context,
            title: 'Você está online!',
            subtitle: 'Buscando corridas disponíveis...',
            type: AppToastType.success,
          );
        }
      } else {
        repo.stopLocationUpdates();
        _runsChannel?.unsubscribe();
        _runsChannel = null;
        await repo.setOnline(user.id, false);
        if (mounted) {
          AppToast.show(
            context,
            title: 'Modo offline ativado',
            subtitle: 'Você não receberá novas corridas',
            type: AppToastType.info,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          title: 'Erro ao alterar status',
          subtitle: e.toString(),
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  void _centerMap() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 15);
    }
  }

  void _showScandalousNewRunModal(double value) {
    if (!mounted) return;
    setState(() => _isShowingModal = true);
    // Beep ou vibração pode ser disparado aqui via packages, mas o visual já é escandaloso
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Nova Corrida',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, a1, a2) => Container(),
      transitionBuilder: (ctx, a1, a2, child) {
        return Transform.scale(
          scale: Curves.elasticOut.transform(a1.value),
          child: Opacity(
            opacity: a1.value,
            child: AlertDialog(
              backgroundColor: AppColors.primaryDeep,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                side: const BorderSide(color: AppColors.primary, width: 4),
              ),
              contentPadding: const EdgeInsets.all(AppSpacing.xl2),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    size: 80,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'NOVA CORRIDA!!!',
                    style: AppTypography.h1.copyWith(
                      color: AppColors.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Você pode faturar agora:\n${CurrencyFormatter.format(value)}',
                    style: AppTypography.h2.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl2),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      onPressed: () {
                        setState(() => _isShowingModal = false);
                        Navigator.pop(ctx);
                        context.push('/motoboy/runs');
                      },
                      child: Text(
                        'ACEITAR AGORA',
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.background,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () {
                      setState(() => _isShowingModal = false);
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Ignorar',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final motoboyAsync = ref.watch(motoboyStreamProvider);
    final user = ref.watch(authNotifierProvider).valueOrNull;
    final activeRunAsync = user != null
        ? ref.watch(activeRunProvider(user.id))
        : null;

    return OfflineBanner(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: motoboyAsync.valueOrNull != null
              ? _MotoboyDrawer(
                  motoboy: motoboyAsync.valueOrNull!,
                  userName: (user?.name.trim().isNotEmpty == true)
                      ? user!.name
                      : (motoboyAsync.valueOrNull!.name.isNotEmpty == true
                            ? motoboyAsync.valueOrNull!.name
                            : 'Entregador'),
                  onSignOut: () async {
                    ref.read(motoboyRepositoryProvider).stopLocationUpdates();
                    await ref.read(authNotifierProvider.notifier).signOut();
                  },
                  onWallet: () {
                    Navigator.of(context).pop();
                    context.push('/motoboy/wallet');
                  },
                  onRuns: () {
                    Navigator.of(context).pop();
                    context.push('/motoboy/runs');
                  },
                  onHistory: () {
                    Navigator.of(context).pop();
                    context.push('/motoboy/history');
                  },
                  onProfile: () {
                    Navigator.of(context).pop();
                    context.push('/motoboy/profile');
                  },
                )
              : null,
          body: motoboyAsync.when(
            loading: () => const _LoadingBody(),
            error: (e, _) => _ErrorBody(
              error: e.toString(),
              onRetry: () => ref.invalidate(motoboyStreamProvider),
            ),
            data: (motoboy) {
              final activeRun = activeRunAsync?.valueOrNull;
              final mapCenter =
                  _currentPosition ??
                  (motoboy.currentLat != null && motoboy.currentLng != null
                      ? LatLng(motoboy.currentLat!, motoboy.currentLng!)
                      : _kDefaultCenter);

              return Stack(
                children: [
                  // ── Mapa de fundo ─────────────────────────────
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: mapCenter,
                      initialZoom: 15.0,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: AppConstants.mapTileUrl,
                        userAgentPackageName: 'com.urbgo.app',
                        maxZoom: 19,
                      ),
                      if (_currentPosition != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentPosition!,
                              width: 80,
                              height: 80,
                              child: _PulsingMarker(
                                animation: _pulseAnimation,
                                isOnline: motoboy.isOnline,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // ── Gradiente topo (header visibility) ────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 160,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.80),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Gradiente base (painel visibility) ────────
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 460,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.96),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Header flutuante ───────────────────────────
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    child: _FloatingHeader(
                      scaffoldKey: _scaffoldKey,
                      isOnline: motoboy.isOnline,
                      onCenterMap: _centerMap,
                    ),
                  ),

                  // ── Painel inferior ────────────────────────────
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _BottomPanel(
                      motoboy: motoboy,
                      isToggling: _isToggling,
                      onToggle: () => _toggleOnline(motoboy.isOnline),
                      activeRun: activeRun,
                      onSeeRuns: () => context.push('/motoboy/runs'),
                      onContinueRun: (id) =>
                          context.push('/motoboy/active/$id'),
                      onWallet: () => context.push('/motoboy/wallet'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ); // OfflineBanner
  }
}

// ─────────────────────────────────────────────────────────────
// Loading / Error
// ─────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
  );
}

class _ErrorBody extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPaddingFull,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Erro: $error',
              style: AppTypography.h4.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
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

// ─────────────────────────────────────────────────────────────
// Header flutuante
// ─────────────────────────────────────────────────────────────

class _FloatingHeader extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool isOnline;
  final VoidCallback onCenterMap;

  const _FloatingHeader({
    required this.scaffoldKey,
    required this.isOnline,
    required this.onCenterMap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Botão menu / hamburger
        _MapFab(
          icon: Icons.menu_rounded,
          onTap: () => scaffoldKey.currentState?.openDrawer(),
        ),

        const Spacer(),

        // Logo centralizada
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: AppSpacing.xs),
            RichText(
              text: TextSpan(
                style: AppTypography.h3,
                children: [
                  const TextSpan(text: 'Urb'),
                  TextSpan(
                    text: 'Go',
                    style: AppTypography.h3.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),

        const Spacer(),

        // Botão centralizar mapa
        _MapFab(
          icon: Icons.my_location_rounded,
          onTap: onCenterMap,
          highlight: isOnline,
        ),
      ],
    );
  }
}

/// Botão circular flutuante sobre o mapa
class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;

  const _MapFab({
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: highlight
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.surfaceBorder,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: highlight ? AppColors.primary : AppColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Marcador animado (pulsante) no mapa
// ─────────────────────────────────────────────────────────────

class _PulsingMarker extends StatelessWidget {
  final Animation<double> animation;
  final bool isOnline;

  const _PulsingMarker({required this.animation, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppColors.primary : AppColors.info;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = animation.value;
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Anel pulsante externo
              if (isOnline)
                Container(
                  width: 72 * t,
                  height: 72 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.25 * (1 - t)),
                  ),
                ),
              // Anel médio estático
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(
                    color: color.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
              ),
              // Ponto central
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Painel inferior
// ─────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final MotoboyModel motoboy;
  final bool isToggling;
  final VoidCallback onToggle;
  final DeliveryModel? activeRun;
  final VoidCallback onSeeRuns;
  final void Function(String id) onContinueRun;
  final VoidCallback onWallet;

  const _BottomPanel({
    required this.motoboy,
    required this.isToggling,
    required this.onToggle,
    required this.activeRun,
    required this.onSeeRuns,
    required this.onContinueRun,
    required this.onWallet,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.xl),
          topRight: Radius.circular(AppRadius.xl),
        ),
        border: Border(
          top: BorderSide(
            color: motoboy.isOnline
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.surfaceBorder,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: motoboy.isOnline
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.black38,
            blurRadius: 32,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle decorativo
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceBorder,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Saudação + saldo ─────────────────
                _GreetingRow(motoboy: motoboy, onWallet: onWallet),
                const SizedBox(height: AppSpacing.md),

                // ── Categoria do veículo ──────────────
                _VehicleCategoryCard(motoboy: motoboy),
                const SizedBox(height: AppSpacing.lg),

                if (!motoboy.isApproved) ...[
                  _ApprovalStatusCard(motoboy: motoboy),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── Toggle online/offline ─────────────
                _OnlineToggle(
                  motoboy: motoboy,
                  isOnline: motoboy.isOnline,
                  isToggling: isToggling,
                  onToggle: onToggle,
                ),

                // ── Ver corridas (online, sem corrida) ─
                if (motoboy.isOnline && activeRun == null) ...[
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: 'Ver Corridas Disponíveis',
                    onPressed: () async {
                      final connected =
                          await ConnectivityService.ensureConnected(
                            context,
                            message:
                                'Conecte-se para carregar corridas disponíveis.',
                          );
                      if (!connected || !context.mounted) return;
                      onSeeRuns();
                    },
                  ),
                ],

                // ── Corrida ativa ─────────────────────
                if (activeRun != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ActiveRunCard(
                    delivery: activeRun!,
                    onContinue: () => onContinueRun(activeRun!.id),
                    onChat: () {
                      final name = Uri.encodeComponent('Cliente');
                      context.push('/motoboy/chat/${activeRun!.id}?name=$name');
                    },
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
          // Respeita a home indicator / navigation bar
          const SafeArea(top: false, child: SizedBox.shrink()),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Saudação + chip de saldo
// ─────────────────────────────────────────────────────────────

class _GreetingRow extends StatelessWidget {
  final MotoboyModel motoboy;
  final VoidCallback onWallet;

  const _GreetingRow({required this.motoboy, required this.onWallet});

  @override
  Widget build(BuildContext context) {
    final firstName = motoboy.name.isNotEmpty
        ? motoboy.name.split(' ').first
        : 'Entregador';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Olá, $firstName', style: AppTypography.h3),
              const SizedBox(height: 3),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: motoboy.isOnline
                          ? AppColors.primary
                          : AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: AppTypography.bodySmall.copyWith(
                      color: motoboy.isOnline
                          ? AppColors.primary
                          : AppColors.textTertiary,
                    ),
                    child: Text(motoboy.isOnline ? 'Online' : 'Offline'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Chip de saldo clicável
        GestureDetector(
          onTap: onWallet,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryDeep,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  CurrencyFormatter.format(motoboy.walletBalance),
                  style: AppTypography.numericMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primary,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Card: Categoria do Veículo
// ─────────────────────────────────────────────────────────────

class _VehicleCategoryCard extends StatelessWidget {
  final MotoboyModel motoboy;

  const _VehicleCategoryCard({required this.motoboy});

  @override
  Widget build(BuildContext context) {
    final info = motoboy.vehicleCategory.info;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(info.icon, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.name, style: AppTypography.labelLarge),
              if (motoboy.vehiclePlate != null)
                Text(
                  motoboy.vehiclePlate!.toUpperCase(),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                    fontFeatures: const [],
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (motoboy.totalRatings > 0) ...[
            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
            const SizedBox(width: 3),
            Text(
              '${motoboy.avgRating.toStringAsFixed(1)} (${motoboy.totalRatings})',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ] else ...[
            Text(
              'Novo',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.primary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Toggle Online / Offline
// ─────────────────────────────────────────────────────────────

class _OnlineToggle extends StatelessWidget {
  final MotoboyModel motoboy;
  final bool isOnline;
  final bool isToggling;
  final VoidCallback onToggle;

  const _OnlineToggle({
    required this.motoboy,
    required this.isOnline,
    required this.isToggling,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final canOperate = motoboy.canGoOnline || isOnline;

    return GestureDetector(
      onTap: isToggling || !canOperate ? null : onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: isOnline
              ? AppColors.primary.withValues(alpha: 0.09)
              : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isOnline
                ? AppColors.primary.withValues(alpha: 0.45)
                : AppColors.surfaceBorder,
          ),
        ),
        child: Row(
          children: [
            // Ícone animado
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isOnline
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  isOnline
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_tethering_off_rounded,
                  key: ValueKey('icon_$isOnline'),
                  color: isOnline ? AppColors.primary : AppColors.textTertiary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: AppTypography.h4.copyWith(
                      color: isOnline
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      layoutBuilder: (cur, prev) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...prev, if (cur != null) cur],
                      ),
                      child: Text(
                        isOnline ? 'Você está online' : 'Você está offline',
                        key: ValueKey('t_$isOnline'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    layoutBuilder: (cur, prev) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...prev, if (cur != null) cur],
                    ),
                    child: Text(
                      isOnline
                          ? 'Recebendo solicitações'
                          : 'Toque para começar a receber',
                      key: ValueKey('s_$isOnline'),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Switch / spinner
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isToggling
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : Switch(
                      key: const ValueKey('switch'),
                      value: isOnline,
                      activeThumbColor: AppColors.primary,
                      activeTrackColor: AppColors.primary.withValues(
                        alpha: 0.28,
                      ),
                      inactiveThumbColor: AppColors.textTertiary,
                      inactiveTrackColor: AppColors.surfaceBorder,
                      onChanged: canOperate ? (_) => onToggle() : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalStatusCard extends StatelessWidget {
  final MotoboyModel motoboy;

  const _ApprovalStatusCard({required this.motoboy});

  @override
  Widget build(BuildContext context) {
    final accent = switch (motoboy.approvalStatus) {
      MotoboyApprovalStatus.rejected => AppColors.error,
      MotoboyApprovalStatus.pendingReview => AppColors.warning,
      _ => AppColors.primary,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: accent, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  motoboy.approvalStatus.label,
                  style: AppTypography.labelLarge.copyWith(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            motoboy.rejectionReason?.trim().isNotEmpty == true
                ? motoboy.rejectionReason!
                : motoboy.approvalStatus.summary,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (motoboy.missingRegistrationItems.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Pendências: ${motoboy.missingRegistrationItems.join(', ')}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (motoboy.approvalStatus == MotoboyApprovalStatus.pendingDocuments) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                onPressed: () => context.push('/motoboy/profile'),
                child: const Text(
                  'Concluir Cadastro',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else if (motoboy.approvalStatus == MotoboyApprovalStatus.pendingReview) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                onPressed: () => context.push('/motoboy/profile'),
                child: const Text('Ver documentos enviados'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Card de corrida ativa
// ─────────────────────────────────────────────────────────────

class _ActiveRunCard extends StatelessWidget {
  final DeliveryModel delivery;
  final VoidCallback onContinue;
  final VoidCallback onChat;

  const _ActiveRunCard({
    required this.delivery,
    required this.onContinue,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header da corrida
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Corrida em andamento',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: delivery.status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  delivery.status.label,
                  style: AppTypography.labelSmall.copyWith(
                    color: delivery.status.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Endereço de coleta
          _AddressLine(
            icon: Icons.radio_button_on_rounded,
            color: AppColors.primary,
            label: 'Coleta',
            address: delivery.pickupAddress,
          ),

          // Linha conectora
          const Padding(
            padding: EdgeInsets.only(left: 7),
            child: SizedBox(
              height: 14,
              child: VerticalDivider(
                color: AppColors.surfaceBorder,
                width: 1,
                thickness: 1,
              ),
            ),
          ),

          // Endereço de entrega
          _AddressLine(
            icon: Icons.location_on_rounded,
            color: AppColors.error,
            label: 'Entrega',
            address: delivery.deliveryAddress,
          ),
          const SizedBox(height: AppSpacing.lg),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text('Chat'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: AppTypography.labelLarge,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: 'Continuar Entrega',
                  onPressed: onContinue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String address;

  const _AddressLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label  ',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                TextSpan(text: address, style: AppTypography.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Menu lateral (Drawer)
// ─────────────────────────────────────────────────────────────

class _MotoboyDrawer extends StatelessWidget {
  final MotoboyModel motoboy;
  final String userName;
  final VoidCallback onSignOut;
  final VoidCallback onWallet;
  final VoidCallback onRuns;
  final VoidCallback onHistory;
  final VoidCallback onProfile;

  const _MotoboyDrawer({
    required this.motoboy,
    required this.userName,
    required this.onSignOut,
    required this.onWallet,
    required this.onRuns,
    required this.onHistory,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : 'M';

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          // ── Cabeçalho do perfil ──────────────────
          // O Container de cor estende atrás da status bar;
          // o SafeArea empurra o conteúdo para baixo dela.
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.surfaceHigh,
              border: Border(
                bottom: BorderSide(color: AppColors.surfaceBorder),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar + Nome + Categoria
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.primaryDeep,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            image:
                                motoboy.avatarUrl != null &&
                                    motoboy.avatarUrl!.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(motoboy.avatarUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child:
                              motoboy.avatarUrl == null ||
                                  motoboy.avatarUrl!.isEmpty
                              ? Center(
                                  child: Text(
                                    initial,
                                    style: AppTypography.h3.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                style: AppTypography.h4,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    motoboy.vehicleCategory.info.icon,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    motoboy.vehicleCategory.info.name,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  if (motoboy.vehiclePlate != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '·  ${motoboy.vehiclePlate!}',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textTertiary,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ), // Column
              ), // Padding
            ), // SafeArea
          ), // Container (header)
          // ── Saldo rápido ─────────────────────────
          GestureDetector(
            onTap: onWallet,
            child: Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                0,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo disponível',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primary.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(motoboy.walletBalance),
                          style: AppTypography.numericLarge.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // ── Separador ────────────────────────────
          const SizedBox(height: AppSpacing.lg),
          const Divider(
            color: AppColors.surfaceBorder,
            indent: AppSpacing.xl,
            endIndent: AppSpacing.xl,
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Itens de navegação ───────────────────
          _DrawerNavItem(
            icon: Icons.home_rounded,
            label: 'Início',
            onTap: () => Navigator.of(context).pop(),
          ),
          _DrawerNavItem(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Carteira',
            onTap: onWallet,
          ),
          _DrawerNavItem(
            icon: Icons.motorcycle_rounded,
            label: 'Corridas',
            onTap: onRuns,
          ),
          _DrawerNavItem(
            icon: Icons.history_rounded,
            label: 'Histórico',
            onTap: onHistory,
          ),
          _DrawerNavItem(
            icon: Icons.person_outline_rounded,
            label: 'Perfil',
            onTap: onProfile,
          ),

          const Spacer(),
          const Divider(
            color: AppColors.surfaceBorder,
            indent: AppSpacing.xl,
            endIndent: AppSpacing.xl,
          ),

          // ── Sair ─────────────────────────────────
          _DrawerNavItem(
            icon: Icons.logout_rounded,
            label: 'Sair',
            color: AppColors.error,
            onTap: onSignOut,
          ),
          const SafeArea(top: false, child: SizedBox.shrink()),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      highlightColor: AppColors.surfaceHigh,
      splashColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color != null
                    ? color!.withValues(alpha: 0.1)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: c, size: 19),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(label, style: AppTypography.h4.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}
