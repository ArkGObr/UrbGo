import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/services/connectivity_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../auth/domain/user_model.dart';
import '../../shared/widgets/delivery_card.dart';
import '../../shared/widgets/category_selector.dart';
import '../domain/client_providers.dart';

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    if (mounted) setState(() => _isLoadingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(pos.latitude, pos.longitude);
            _isLoadingLocation = false;
          });
          _mapController.move(_currentPosition!, 15.0);
        }
      } else {
        if (mounted) setState(() => _isLoadingLocation = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _onCategorySelected(VehicleCategoryInfo cat) async {
    final connected = await ConnectivityService.ensureConnected(
      context,
      message: 'Conecte-se à internet para criar uma entrega.',
    );
    if (!connected || !mounted) return;
    context.push('/client/create', extra: cat);
  }

  @override
  Widget build(BuildContext context) {
    final deliveriesAsync = ref.watch(clientDeliveriesProvider);
    final user = ref.watch(authNotifierProvider).valueOrNull;

    return OfflineBanner(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: user != null
              ? _ClientDrawer(
                  user: user,
                  onHome: () => Navigator.of(context).pop(),
                  onHistory: () {
                    Navigator.of(context).pop();
                    context.push('/client/history');
                  },
                  onProfile: () {
                    Navigator.of(context).pop();
                    context.push('/client/profile');
                  },
                  onSignOut: () async {
                    Navigator.of(context).pop();
                    await ref.read(authNotifierProvider.notifier).signOut();
                  },
                )
              : null,
          body: Stack(
            children: [
              // ── Mapa de fundo ──────────────────────
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _currentPosition ?? const LatLng(-23.5505, -46.6333),
                    initialZoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: AppConstants.mapTileUrl,
                      userAgentPackageName: 'com.appmoove.urbgo',
                    ),
                    if (_currentPosition != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentPosition!,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2196F3),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // ── Header flutuante ───────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + AppSpacing.md,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Botão de menu → abre drawer
                    _FloatingIconButton(
                      icon: Icons.menu_rounded,
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),

                    // Logo central
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/logo.png',
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          RichText(
                            text: TextSpan(
                              style: AppTypography.h3.copyWith(height: 1.2),
                              children: const [
                                TextSpan(
                                  text: 'Urb',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Go',
                                  style: TextStyle(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Botão de localização
                    _FloatingIconButton(
                      icon: Icons.my_location_rounded,
                      iconColor: AppColors.primary,
                      onPressed: _isLoadingLocation ? null : _getUserLocation,
                    ),
                  ],
                ),
              ),

              // ── Painel inferior ────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomCard(deliveriesAsync),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCard(AsyncValue deliveriesAsync) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Barra de busca
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: GestureDetector(
                onTap: () async {
                  final connected = await ConnectivityService.ensureConnected(
                    context,
                    message: 'Conecte-se à internet para criar uma entrega.',
                  );
                  if (!connected || !mounted) return;
                  context.push('/client/create');
                },
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        'Para onde vamos?',
                        style: AppTypography.h3.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl2),

            // Categorias
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Escolha uma categoria', style: AppTypography.h4),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: CategorySelectorWidget(
                isForDriver: false,
                onSelected: _onCategorySelected,
              ),
            ),
            const SizedBox(height: AppSpacing.xl2),

            // Entregas em andamento
            deliveriesAsync.when(
              data: (deliveries) {
                final active = (deliveries as List)
                    .where((d) => d.isActive)
                    .toList();
                if (active.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Text('Em andamento', style: AppTypography.h4),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 232,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: active.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.md),
                        itemBuilder: (_, i) => SizedBox(
                          width:
                              MediaQuery.of(context).size.width -
                              (AppSpacing.lg * 2),
                          child: DeliveryCard(
                            delivery: active[i],
                            index: i,
                            compact: true,
                            onChatTap: active[i].motoboyId == null
                                ? null
                                : () {
                                    final name = Uri.encodeComponent(
                                      active[i].motoboyName ?? 'Entregador',
                                    );
                                    context.push(
                                      '/client/chat/${active[i].id}?name=$name',
                                    );
                                  },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 40,
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Botão flutuante circular ──────────────────────────────────
class _FloatingIconButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onPressed;

  const _FloatingIconButton({
    required this.icon,
    this.iconColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor ?? AppColors.textPrimary),
        onPressed: onPressed,
      ),
    );
  }
}

// ── Drawer lateral do cliente ─────────────────────────────────
class _ClientDrawer extends StatelessWidget {
  final UserModel user;
  final VoidCallback onHome;
  final VoidCallback onHistory;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;

  const _ClientDrawer({
    required this.user,
    required this.onHome,
    required this.onHistory,
    required this.onProfile,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'C';

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          // ── Cabeçalho do perfil ──────────────────
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
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primaryDeep,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        image:
                            user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(user.avatarUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: user.avatarUrl == null || user.avatarUrl!.isEmpty
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
                            user.name,
                            style: AppTypography.h4,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Cliente',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

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
            onTap: onHome,
          ),
          _DrawerNavItem(
            icon: Icons.receipt_long_rounded,
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

// ── Item do drawer ────────────────────────────────────────────
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
