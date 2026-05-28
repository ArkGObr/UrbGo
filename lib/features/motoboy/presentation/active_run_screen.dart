import 'dart:async';
import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/route_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/route_result.dart' as smart_route;
import '../../client/data/delivery_repository.dart';
import '../../client/domain/delivery_model.dart';
import '../../delivery/domain/delivery_session.dart';
import '../../delivery/presentation/widgets/copilot_speed_indicator.dart';
import '../../delivery/presentation/widgets/copilot_status_bar.dart';
import '../../delivery/presentation/widgets/copilot_settings_sheet.dart';
import '../../delivery/presentation/widgets/reroute_comparison_sheet.dart';
import '../../delivery/services/copilot_service.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../domain/motoboy_providers.dart';

/// Provider local para a posição do motoboy em tempo real
final _myPositionProvider = StateProvider<LatLng?>((ref) => null);

enum _ExternalNavigationApp {
  googleMaps,
  waze,
  appleMaps,
  browser,
}

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

  DeliveryModel? _delivery;
  bool _isLoading = true;
  bool _isProcessing = false;
  List<LatLng> _routePoints = [];

  // Variáveis para cache da API de Rotas (OSRM)
  DateTime? _lastOsrmFetch;
  RouteResult? _lastRouteResult;
  StreamSubscription<String>? _actionSub;

  @override
  void initState() {
    super.initState();
    _startPositionStream();
    _startGpsMonitor();
    _loadDelivery();
    _actionSub = ref.read(notificationServiceProvider).onAction.listen((
      actionId,
    ) {
      if (!mounted) return;
      if (actionId == 'confirm_pickup' && _delivery != null) {
        _processPickupConfirmation(_delivery!.id, fromNotification: true);
      } else if (actionId == 'complete_delivery' && _delivery != null) {
        _processDeliveryCompletion(_delivery!);
      }
    });
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
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.primary,
              ),
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

      // Atualiza a notificação de andamento imediatamente (para não depender apenas do movimento do GPS)
      final currentPos = ref.read(_myPositionProvider);
      if (currentPos != null) {
        _updateNotificationStatus(currentPos);
      }

      // Carrega a rota real após ter as coordenadas
      final pickup = LatLng(delivery.pickupLat, delivery.pickupLng);
      final stops = [
        pickup,
        if (delivery.extraStopLat != null && delivery.extraStopLng != null)
          LatLng(delivery.extraStopLat!, delivery.extraStopLng!),
        LatLng(delivery.deliveryLat, delivery.deliveryLng),
      ];
      _loadRoute(stops);
    } catch (e, stack) {
      Logger.error('ActiveRunScreen._loadDelivery', e, stack);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRoute(List<LatLng> stops) async {
    if (stops.isEmpty) return;
    if (mounted) setState(() => _routePoints = stops);
    try {
      final route = await _routeService.getRouteWithStops(stops);
      final points = route.points;
      if (mounted) {
        setState(() => _routePoints = points);
        _fitBounds();
      }
      if (_delivery != null) {
        ref
            .read(copilotServiceProvider.notifier)
            .startMonitoring(
              DeliverySession(
                deliveryId: _delivery!.id,
                destination: stops.last,
                routeResult: smart_route.RouteResult(
                  distanceMeters: route.distanceKm * 1000,
                  durationSeconds: route.durationSeconds,
                  durationInTrafficSeconds: route.durationSeconds,
                  source: smart_route.RouteSource.osrm,
                  polyline: route.points,
                  trafficRatio: 1,
                  computedAt: DateTime.now(),
                ),
              ),
            );
      }
    } catch (_) {}
  }

  void _fitBounds() {
    if (_delivery == null) return;
    final bool goingToPickup = _delivery!.status == DeliveryStatus.accepted;
    final dest = goingToPickup
        ? LatLng(_delivery!.pickupLat, _delivery!.pickupLng)
        : LatLng(_delivery!.deliveryLat, _delivery!.deliveryLng);
    final start =
        ref.read(_myPositionProvider) ??
        LatLng(_delivery!.pickupLat, _delivery!.pickupLng);

    try {
      if (start == dest) {
        _mapController.move(dest, 16);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(start, dest),
          padding: const EdgeInsets.all(50),
        ),
      );
    } catch (_) {}
  }

  void _startPositionStream() {
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2, // Frequência maior para navegação fluida
            // Para rastreamento em segundo plano robusto seria necessário um serviço de foreground.
            // Aqui estamos mantendo o GPS no foreground enquanto o App estiver ativo.
          ),
        ).listen((pos) {
          if (!mounted) return;
          final latLng = LatLng(pos.latitude, pos.longitude);
          ref.read(_myPositionProvider.notifier).state = latLng;
          _updateNotificationStatus(latLng);
        });
  }

  void _updateNotificationStatus(LatLng currentPos) {
    if (_delivery == null) return;

    final bool goingToPickup = _delivery!.status == DeliveryStatus.accepted;
    final routeStops = <LatLng>[
      currentPos,
      if (goingToPickup)
        LatLng(_delivery!.pickupLat, _delivery!.pickupLng)
      else ...[
        if (_delivery!.extraStopLat != null && _delivery!.extraStopLng != null)
          LatLng(_delivery!.extraStopLat!, _delivery!.extraStopLng!),
        LatLng(_delivery!.deliveryLat, _delivery!.deliveryLng),
      ],
    ];
    final dest = routeStops.last;

    final now = DateTime.now();
    // Busca na API de Rotas a cada 20 segundos para não estourar limite
    if (_lastOsrmFetch == null ||
        now.difference(_lastOsrmFetch!).inSeconds > 20) {
      _lastOsrmFetch = now;
      _routeService
          .getRouteWithStops(routeStops)
          .then((routeResult) {
            if (!mounted) return;
            _lastRouteResult = routeResult;
            // Atualiza a notificação imediatamente após chegada do OSRM
            _dispatchNotification(currentPos, goingToPickup, dest);
          })
          .catchError((_) {});
    } else {
      // Usa o cache enquanto a API não refaz a busca
      _dispatchNotification(currentPos, goingToPickup, dest);
    }
  }

  void _dispatchNotification(
    LatLng currentPos,
    bool goingToPickup,
    LatLng dest,
  ) {
    if (_delivery == null) return;

    double displayKm;
    int minutes;

    if (_lastRouteResult != null) {
      // Usa os dados precisos em tempo real da API de roteamento
      displayKm = _lastRouteResult!.distanceKm;
      // Ajusta ligeiramente a distância real no intervalo dos 20 segundos
      // subtraindo o que ele caminhou em linha reta desde que o cache rodou.
      // (Para simplificar, apenas usamos o distanceKm mais recente do cache, que atualiza a cada 20s)
      minutes = (_lastRouteResult!.durationSeconds / 60).round();
    } else {
      // Fallback: Estimativa em linha reta local
      final distanceMeters = const Distance().as(
        LengthUnit.Meter,
        currentPos,
        dest,
      );
      displayKm = (distanceMeters / 1000) * 1.4;
      minutes = ((displayKm / 35.0) * 60).round();
    }

    // Evita valores zerados bizarros
    if (minutes < 1) minutes = 1;
    if (displayKm < 0.1) displayKm = 0.1;

    final formattedKm = displayKm.toStringAsFixed(1);
    final title = goingToPickup
        ? 'Indo para o Local de Coleta'
        : 'A Caminho da Entrega';
    final destinationLabel = goingToPickup
        ? _delivery!.pickupAddress
        : _delivery!.deliveryAddress;
    final body =
        '$formattedKm km restantes • ~ $minutes min\nDestino: $destinationLabel';

    try {
      ref
          .read(notificationServiceProvider)
          .showOngoingRunNotification(
            title: title,
            body: body,
            goingToPickup: goingToPickup,
            deliveryId: _delivery!.id,
          );
    } catch (_) {}
  }

  String get _navigationTravelMode {
    final category = _delivery?.vehicleCategory;
    if (category == VehicleCategory.bike) return 'bicycling';
    return 'driving';
  }

  String _buildGoogleMapsWebUrl({
    required LatLng destination,
    String? waypoint,
  }) {
    return 'https://www.google.com/maps/dir/?api=1'
        '&destination=${destination.latitude},${destination.longitude}'
        '${waypoint != null ? '&waypoints=$waypoint' : ''}'
        '&travelmode=$_navigationTravelMode';
  }

  Future<bool> _launchExternalNavigation(_ExternalNavigationApp app) async {
    final delivery = _delivery;
    if (delivery == null) return false;

    final goingToPickup = delivery.status == DeliveryStatus.accepted;
    final destination = goingToPickup
        ? LatLng(delivery.pickupLat, delivery.pickupLng)
        : LatLng(delivery.deliveryLat, delivery.deliveryLng);
    final waypoint =
        !goingToPickup &&
            delivery.extraStopLat != null &&
            delivery.extraStopLng != null
        ? '${delivery.extraStopLat},${delivery.extraStopLng}'
        : null;

    final googleWebUri = Uri.parse(
      _buildGoogleMapsWebUrl(destination: destination, waypoint: waypoint),
    );

    final candidateUris = switch (app) {
      _ExternalNavigationApp.googleMaps => [
          if (Platform.isAndroid && waypoint == null)
            Uri.parse(
              'google.navigation:q=${destination.latitude},${destination.longitude}'
              '&mode=${_navigationTravelMode == 'bicycling' ? 'l' : 'd'}',
            ),
          if (Platform.isIOS)
            Uri.parse(
              'comgooglemaps://?daddr=${destination.latitude},${destination.longitude}'
              '&directionsmode=$_navigationTravelMode',
            ),
          googleWebUri,
        ],
      _ExternalNavigationApp.waze => [
          Uri.parse(
            'waze://?ll=${destination.latitude},${destination.longitude}&navigate=yes',
          ),
          Uri.parse(
            'https://waze.com/ul?ll=${destination.latitude},${destination.longitude}&navigate=yes',
          ),
        ],
      _ExternalNavigationApp.appleMaps => [
          Uri.parse(
            'maps://?daddr=${destination.latitude},${destination.longitude}'
            '&dirflg=${_navigationTravelMode == 'bicycling' ? 'w' : 'd'}',
          ),
        ],
      _ExternalNavigationApp.browser => [googleWebUri],
    };

    for (final uri in candidateUris) {
      if (!await canLaunchUrl(uri)) continue;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }

    return false;
  }

  Future<void> _openExternalNavigationPicker() async {
    final delivery = _delivery;
    if (delivery == null) return;

    final app = await showModalBottomSheet<_ExternalNavigationApp>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        final options = <({
          _ExternalNavigationApp app,
          IconData icon,
          String title,
          String subtitle,
        })>[
          (
            app: _ExternalNavigationApp.googleMaps,
            icon: Icons.map_rounded,
            title: 'Google Maps',
            subtitle: 'Abrir rota no Google Maps',
          ),
          (
            app: _ExternalNavigationApp.waze,
            icon: Icons.navigation_rounded,
            title: 'Waze',
            subtitle: 'Abrir rota no Waze',
          ),
          if (Platform.isIOS)
            (
              app: _ExternalNavigationApp.appleMaps,
              icon: Icons.directions_car_filled_rounded,
              title: 'Apple Maps',
              subtitle: 'Abrir rota no Apple Maps',
            ),
          (
            app: _ExternalNavigationApp.browser,
            icon: Icons.open_in_browser_rounded,
            title: 'Abrir no navegador',
            subtitle: 'Usar o link externo da rota',
          ),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Escolha o app de navegação', style: AppTypography.h3),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'A rota será aberta fora do app para você usar o navegador de sua preferência.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final option in options) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(option.icon, color: AppColors.primary),
                    title: Text(option.title, style: AppTypography.labelLarge),
                    subtitle: Text(
                      option.subtitle,
                      style: AppTypography.bodySmall,
                    ),
                    onTap: () => Navigator.of(context).pop(option.app),
                  ),
                  if (option != options.last)
                    const Divider(color: AppColors.surfaceBorder, height: 1),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (app == null) return;

    try {
      final launched = await _launchExternalNavigation(app);
      if (launched || !mounted) return;

      AppToast.show(
        context,
        title: 'App indisponível',
        subtitle: 'Não foi possível abrir o app selecionado neste dispositivo.',
        type: AppToastType.error,
      );
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          title: 'Erro ao abrir mapa',
          subtitle: 'Não foi possível iniciar a navegação externa.',
          type: AppToastType.error,
        );
      }
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _gpsStatusSub?.cancel();
    _actionSub?.cancel();
    _mapController.dispose();
    try {
      ref.read(notificationServiceProvider).cancelOngoingRunNotification();
    } catch (_) {}
    ref.read(copilotServiceProvider.notifier).stopMonitoring();
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
            child: Text(
              'Cancelar',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Confirmar',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _processPickupConfirmation(deliveryId);
  }

  Future<void> _processPickupConfirmation(
    String deliveryId, {
    bool fromNotification = false,
  }) async {
    setState(() => _isProcessing = true);
    try {
      await ref.read(motoboyRepositoryProvider).confirmPickup(deliveryId);
      await _loadDelivery();
      if (mounted) {
        AppToast.show(
          context,
          title: 'Coleta confirmada!',
          subtitle: 'Agora siga para o ponto de entrega',
          type: AppToastType.success,
        );
      }

      // Quando confirmado PELA NOTIFICAÇÃO, leva ao Maps automaticamente
      if (fromNotification && mounted) {
        await Future.delayed(const Duration(milliseconds: 300));
        _openExternalNavigationPicker();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          title: 'Erro ao confirmar coleta',
          subtitle: e.toString(),
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _abandonDelivery(String deliveryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Desistir da Corrida?', style: AppTypography.h3),
        content: Text(
          'A corrida voltará para o pool de disponíveis. Isso pode afetar sua reputação.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Desistir',
              style: AppTypography.labelLarge.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isProcessing = true);
    try {
      await ref.read(motoboyRepositoryProvider).abandonDelivery(deliveryId);
      ref.invalidate(availableRunsProvider);
      if (mounted) context.go('/motoboy/home');
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          title: 'Erro ao desistir',
          subtitle: e.toString(),
          type: AppToastType.error,
        );
        setState(() => _isProcessing = false);
      }
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
            child: Text(
              'Cancelar',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Finalizar',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _processDeliveryCompletion(delivery);
  }

  Future<void> _processDeliveryCompletion(DeliveryModel delivery) async {
    // Tenta capturar foto de confirmação (opcional — pode pular)
    File? photoFile;
    if (mounted) {
      final picker = ImagePicker();
      final shouldPhoto = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          title: Text('Foto de entrega', style: AppTypography.h3),
          content: Text(
            'Tire uma foto do pacote entregue para confirmar. Opcional, mas recomendado.',
            style: AppTypography.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Pular',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Tirar foto',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      );
      if (shouldPhoto == true && mounted) {
        final xFile = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 75,
          maxWidth: 1280,
        );
        if (xFile != null) photoFile = File(xFile.path);
      }
    }

    setState(() => _isProcessing = true);
    try {
      await ref.read(motoboyRepositoryProvider).completeDelivery(delivery.id);
      // Upload da foto se capturada
      if (photoFile != null) {
        try {
          await DeliveryRepository().uploadDeliveryPhoto(
            delivery.id,
            photoFile,
          );
        } catch (_) {
          // Falha no upload não bloqueia a conclusão
        }
      }
      ref.invalidate(availableRunsProvider);
      ref.invalidate(motoboyStreamProvider);
      if (mounted) {
        await _showSuccessDialog(delivery.netEarnings, delivery.commission);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          title: 'Erro ao finalizar entrega',
          subtitle: e.toString(),
          type: AppToastType.error,
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
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.primary,
                size: 40,
              ),
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
                      Text('Comissão', style: AppTypography.bodySmall),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Descontado: ${CurrencyFormatter.format(commission)}',
                          textAlign: TextAlign.right,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                      Text(
                        'Você deve receber',
                        style: AppTypography.labelLarge,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          CurrencyFormatter.format(earnings),
                          textAlign: TextAlign.right,
                          style: AppTypography.numericLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
    final copilotState = ref.watch(copilotServiceProvider);

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
    final extraStopLatLng =
        (delivery.extraStopLat != null && delivery.extraStopLng != null)
        ? LatLng(delivery.extraStopLat!, delivery.extraStopLng!)
        : null;

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
                      userAgentPackageName: 'com.arkgo.app',
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
                            child: const Icon(
                              Icons.store_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
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
                                  color: AppColors.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 8,
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
                        // Parada extra
                        if (extraStopLatLng != null)
                          Marker(
                            point: extraStopLatLng,
                            width: 36,
                            height: 36,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFF9800,
                                    ).withValues(alpha: 0.4),
                                    blurRadius: 8,
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
                                    color: AppColors.info.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Icon(
                                delivery.vehicleCategory.info.icon,
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
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                ),

                // Botão chat
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: AppSpacing.lg,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: AppColors.surface,
                            builder: (_) => const CopilotSettingsSheet(),
                          );
                        },
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
                            Icons.tune_rounded,
                            color: AppColors.textPrimary,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      GestureDetector(
                        onTap: () {
                          final name = Uri.encodeComponent('Cliente');
                          context.push(
                            '/motoboy/chat/${delivery.id}?name=$name',
                          );
                        },
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
                            Icons.chat_bubble_outline_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (copilotState.isMonitoring)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 72,
                    right: AppSpacing.lg,
                    child: CopilotSpeedIndicator(
                      currentSpeed: copilotState.currentSpeedKmh,
                      expectedSpeed: copilotState.expectedSpeedKmh,
                      ratio: copilotState.ratio,
                    ),
                  ),

                // Botão navegar (estilo Uber)
                Positioned(
                  bottom: AppSpacing.lg,
                  right: AppSpacing.lg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
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
                        onTap: _openExternalNavigationPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.navigation_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Abrir navegação',
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
                if (copilotState.isMonitoring)
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    bottom: 88,
                    child: CopilotStatusBar(
                      state: copilotState,
                      onIgnore: () {
                        ref
                            .read(copilotServiceProvider.notifier)
                            .dismissAlert();
                      },
                      onSeeReroute: () {
                        final currentRoute = smart_route.RouteResult(
                          distanceMeters:
                              (_lastRouteResult?.distanceKm ?? 0) * 1000,
                          durationSeconds:
                              _lastRouteResult?.durationSeconds ?? 0,
                          durationInTrafficSeconds:
                              _lastRouteResult?.durationSeconds ?? 0,
                          source: smart_route.RouteSource.osrm,
                          polyline: _routePoints,
                          trafficRatio: 1,
                          computedAt: DateTime.now(),
                        );
                        final alternativeRoute = copilotState.suggestedRoute;
                        if (alternativeRoute == null) return;
                        showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: AppColors.surface,
                          isScrollControlled: true,
                          builder: (_) => RerouteComparisonSheet(
                            currentRoute: currentRoute,
                            alternativeRoute: alternativeRoute,
                            onConfirm: () {
                              Navigator.pop(context);
                              setState(
                                () => _routePoints = alternativeRoute.polyline,
                              );
                              ref
                                  .read(copilotServiceProvider.notifier)
                                  .acceptReroute(alternativeRoute);
                            },
                          ),
                        );
                      },
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
              border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
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
                              color: delivery.status.color.withValues(
                                alpha: 0.3,
                              ),
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
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Valor + distância
                    Row(
                      children: [
                        Text('Você recebe', style: AppTypography.bodyMedium),
                        const Spacer(),
                        if (delivery.distanceKm != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceBorder.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.straighten_rounded,
                                  size: 11,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${delivery.distanceKm!.toStringAsFixed(1)} km',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Text(
                          CurrencyFormatter.format(delivery.netEarnings),
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
                    if (delivery.extraStopAddress != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _AddressRow(
                        icon: Icons.add_location_alt_rounded,
                        iconColor: const Color(0xFFFF9800),
                        label: 'Parada extra',
                        address: delivery.extraStopAddress!,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _AddressRow(
                      icon: Icons.flag_rounded,
                      iconColor: AppColors.primary,
                      label: 'Entrega',
                      address: delivery.deliveryAddress,
                    ),
                    const SizedBox(height: AppSpacing.xl2),

                    // Botões de ação SEMPRE VISÍVEIS no modo direção
                    if (delivery.status == DeliveryStatus.accepted) ...[
                      PrimaryButton(
                        label: '✓ Confirmar Coleta',
                        onPressed: _isProcessing
                            ? null
                            : () => _confirmPickup(delivery.id),
                        isLoading: _isProcessing,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _abandonDelivery(delivery.id),
                          child: Text(
                            'Desistir da Corrida',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ),
                    ],
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
