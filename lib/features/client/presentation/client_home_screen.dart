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
import '../../shared/widgets/delivery_card.dart';
import '../../shared/widgets/category_selector.dart';
import '../domain/client_providers.dart';

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(pos.latitude, pos.longitude);
            _isLoadingLocation = false;
          });
          // Anima / Move o mapa para a localização do usuário
          _mapController.move(_currentPosition!, 15.0);
        }
      } else {
        setState(() => _isLoadingLocation = false);
      }
    } catch (_) {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _onCategorySelected(VehicleCategoryInfo cat) {
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
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // 1. MAPA DE FUNDO
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition ?? const LatLng(-23.5505, -46.6333),
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
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // 2. HEADER FLUTUANTE
              Positioned(
                top: MediaQuery.of(context).padding.top + AppSpacing.md,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: _buildFloatingHeader(user?.name ?? ''),
              ),

              // 3. BARRA INFERIOR DE OPÇÕES (draggable / posicionado)
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

  // HEADER COM LOGO E FOTO
  Widget _buildFloatingHeader(String userName) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Drawer Menu / Perfil
        Container(
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
            icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
            onPressed: () {
              // Poderia abrir um Drawer, aqui vou dar logout rápido apenas para funcionalidade base
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.surface,
                builder: (_) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_rounded),
                        title: Text('Olá, ${userName.isNotEmpty ? userName : 'Cliente'}', style: AppTypography.h4),
                      ),
                      ListTile(
                        leading: const Icon(Icons.manage_accounts_rounded),
                        title: Text('Meu Perfil', style: AppTypography.bodyLarge),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/client/profile');
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                        title: Text('Sair da conta', style: AppTypography.bodyLarge.copyWith(color: AppColors.error)),
                        onTap: () async {
                          Navigator.pop(context);
                          await ref.read(authNotifierProvider.notifier).signOut();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        // Center Banner: Logo + App Name
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
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
                  children: [
                    const TextSpan(text: 'Urb', style: TextStyle(color: AppColors.textPrimary)),
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

        // Usado para equilibrar o lado direito no Row (spaceBetween)
        const SizedBox(width: 48), 
      ],
    );
  }

  // PAINEL INFERIOR COM A BUSCA E CATEGORIAS
  Widget _buildBottomCard(AsyncValue deliveriesAsync) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
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

            // Onde vamos? Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: GestureDetector(
                onTap: () => context.push('/client/create'),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 24),
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

            // Widget de Categorias refeito para ser um Wrap!
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
                isForDriver: false, // Cliente
                onSelected: _onCategorySelected,
              ),
            ),

            const SizedBox(height: AppSpacing.xl2),
            
            // Entregas recentes (apenas scroll horizontal ou lista pequena)
            deliveriesAsync.when(
              data: (deliveries) {
                if (deliveries.isEmpty) return const SizedBox.shrink();
                
                final active = (deliveries as List).where((d) => d.isActive).toList();
                if (active.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Text('Em andamento', style: AppTypography.h4),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 220,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        scrollDirection: Axis.horizontal,
                        itemCount: active.length,
                        separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.md),
                        itemBuilder: (context, index) {
                          return SizedBox(
                            width: MediaQuery.of(context).size.width - (AppSpacing.lg * 2),
                            child: DeliveryCard(delivery: active[index], index: index),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                );
              },
              loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
