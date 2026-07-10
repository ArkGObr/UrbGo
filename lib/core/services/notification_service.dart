import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _kUrgentVibrationPattern = Int64List.fromList([
  0,
  700,
  250,
  900,
  250,
  900,
]);

// Canal principal — corridas, status, saldo
final _kAndroidChannel = AndroidNotificationChannel(
  'arkgo_urgent_channel',
  'ArkGo Urgente',
  description: 'Notificações urgentes de corridas, status e atendimento',
  importance: Importance.max,
  playSound: true,
  sound: const RawResourceAndroidNotificationSound('arkgo_alert'),
  enableVibration: true,
  vibrationPattern: _kUrgentVibrationPattern,
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

// Canal para notificações de re-engajamento (inatividade)
const _kReengagementChannel = AndroidNotificationChannel(
  'arkgo_reengagement',
  'ArkGo — Lembretes',
  description: 'Lembretes para voltar a fazer entregas',
  importance: Importance.defaultImportance,
  playSound: true,
  enableVibration: true,
);

DarwinNotificationDetails get _kDarwinUrgentDetails =>
    const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      sound: 'default',
      interruptionLevel: InterruptionLevel.active,
    );

AndroidNotificationDetails get _kAndroidUrgentDetails =>
    AndroidNotificationDetails(
      _kAndroidChannel.id,
      _kAndroidChannel.name,
      channelDescription: _kAndroidChannel.description,
      icon: 'ic_notification',
      color: const Color(0xFF99eb09),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('arkgo_alert'),
      enableVibration: true,
      vibrationPattern: _kUrgentVibrationPattern,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
    );

/// Handler de background — top-level obrigatório; roda em isolate separado.
/// Cuida apenas de mensagens data-only (sem campo `notification`).
/// Mensagens com `notification` já são exibidas automaticamente pelo SO.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Mensagens com payload de notification → SO já exibe automaticamente.
  if (message.notification != null) return;

  // Data-only: precisamos exibir manualmente.
  await Firebase.initializeApp();

  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_kAndroidChannel);

  final title = message.data['title'] as String? ?? 'ArkGo';
  final body = message.data['body'] as String? ?? '';
  if (title.isEmpty) return;

  await local.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: _kAndroidUrgentDetails,
      iOS: _kDarwinUrgentDetails,
    ),
    payload: message.data['deliveryId'],
  );
}

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // GoRouter é injetado para permitir navegação por tap na notificação
  String Function(String deliveryId)? _clientTrackingPath;
  String Function(String deliveryId)? _motoboyActivePath;

  /// Injeta callbacks de navegação (chamado em main.dart ou SplashScreen)
  void setNavigationCallbacks({
    required String Function(String id) clientTracking,
    required String Function(String id) motoboyActive,
  }) {
    _clientTrackingPath = clientTracking;
    _motoboyActivePath = motoboyActive;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // 1. Solicitar permissão (iOS + Android 13+)
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      // 2. Inicializar flutter_local_notifications
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _onLocalTap,
      );

      // 3. Criar canais Android
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_kAndroidChannel);
      await androidPlugin?.createNotificationChannel(_kReengagementChannel);
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'ongoing_run_channel',
          'Corrida em andamento',
          description: 'Acompanhamento em tempo real da rota',
          importance: Importance.low,
        ),
      );

      // 4. Foreground: exibir notificação local
      FirebaseMessaging.onMessage.listen(_showLocal);

      // 5. Background → foreground: navegar ao tocar
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteNavigation);

      // 6. App estava terminado e foi aberto pela notificação
      final initial = await _fcm.getInitialMessage();
      if (initial != null) _handleRemoteNavigation(initial);
    } catch (e, stack) {
      debugPrint('[FCM] Erro ao inicializar notificações: $e\n$stack');
    }
  }

  /// Salva o FCM token do usuário no banco e registra listener de renovação
  Future<void> saveToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;
      await _persistToken(userId, token);

      // Renovação automática de token pelo Firebase
      _fcm.onTokenRefresh.listen((newToken) => _persistToken(userId, newToken));
    } catch (e) {
      debugPrint('[FCM] Erro ao salvar token: $e');
    }
  }

  Future<void> _persistToken(String userId, String token) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (e) {
      debugPrint('[FCM] Erro ao persistir token: $e');
    }
  }

  /// Remove o token ao fazer logout (evita notificações indevidas)
  Future<void> clearToken(String userId) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': null})
          .eq('id', userId);
      await _fcm.deleteToken();
    } catch (_) {}
  }

  // ── Privados ────────────────────────────────────────────────

  void _showLocal(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;

    _local.show(
      message.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: _kAndroidUrgentDetails,
        iOS: _kDarwinUrgentDetails,
      ),
      payload: message.data['deliveryId'],
    );
  }

  // ── Ações Customizadas das Notificações ───────────────────────
  final _actionStreamController = StreamController<String>.broadcast();
  Stream<String> get onAction => _actionStreamController.stream;

  // ── Atualização Contínua em Tempo Real ────────────────────────

  Future<void> showOngoingRunNotification({
    required String title,
    required String body,
    required bool goingToPickup,
    required String deliveryId,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'ongoing_run_channel',
      'Corrida em andamento',
      channelDescription: 'Acompanhamento em tempo real da rota',
      icon: 'ic_notification',
      color: const Color(0xFF99eb09),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showWhen: false,
      actions: [
        if (goingToPickup)
          const AndroidNotificationAction(
            'confirm_pickup',
            'Confirmar Coleta',
            showsUserInterface: true,
          )
        else
          const AndroidNotificationAction(
            'complete_delivery',
            'Finalizar Entrega',
            showsUserInterface: true,
          ),
      ],
    );

    // Android: usa Foreground Service para manter GPS ativo em segundo plano
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.startForegroundService(
        9999,
        title,
        body,
        notificationDetails: androidDetails,
        payload: deliveryId,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeLocation,
        },
      );
    } else {
      await _local.show(
        9999,
        title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
        payload: deliveryId,
      );
    }
  }

  Future<void> cancelOngoingRunNotification() async {
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.stopForegroundService();
    } else {
      await _local.cancel(9999);
    }
  }

  Future<void> showClientAlert({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _local.show(
      7777,
      title,
      body,
      NotificationDetails(
        android: _kAndroidUrgentDetails,
        iOS: _kDarwinUrgentDetails,
      ),
      payload: payload,
    );
  }

  Future<void> showNewDeliveryAlarm({
    required String deliveryId,
    required String title,
    required String body,
  }) async {
    await HapticFeedback.heavyImpact();
    await _local.show(
      deliveryId.hashCode,
      title,
      body,
      NotificationDetails(
        android: _kAndroidUrgentDetails,
        iOS: _kDarwinUrgentDetails,
      ),
      payload: 'motoboy|new_delivery|$deliveryId',
    );
  }

  void _onLocalTap(NotificationResponse response) {
    if (response.actionId != null) {
      _actionStreamController.add(response.actionId!);
    } else {
      final parsed = _parseLocalPayload(response.payload);
      _navigate(parsed.deliveryId, parsed.role, type: parsed.type);
    }
  }

  void _handleRemoteNavigation(RemoteMessage message) {
    final deliveryId = message.data['deliveryId'] as String?;
    final role = message.data['role'] as String?;
    final type = message.data['type'] as String?;
    _navigate(deliveryId, role, type: type);
  }

  ({String? deliveryId, String? role, String? type}) _parseLocalPayload(
    String? payload,
  ) {
    if (payload == null || payload.isEmpty) {
      return (deliveryId: null, role: null, type: null);
    }

    final parts = payload.split('|');
    if (parts.length == 3) {
      return (role: parts[0], type: parts[1], deliveryId: parts[2]);
    }

    return (deliveryId: payload, role: null, type: null);
  }

  void _navigate(String? deliveryId, String? role, {String? type}) {
    if (deliveryId == null) return;

    switch (type) {
      case 'new_delivery':
        _pendingRoute = '/motoboy/runs';

      case 'new_message':
        _pendingRoute = role == 'motoboy'
            ? '/motoboy/chat/$deliveryId'
            : '/client/chat/$deliveryId';

      default:
        // Status de entrega (accepted, in_progress, completed, cancelled)
        if (role == 'motoboy' && _motoboyActivePath != null) {
          _pendingRoute = _motoboyActivePath!(deliveryId);
        } else if (_clientTrackingPath != null) {
          _pendingRoute = _clientTrackingPath!(deliveryId);
        }
    }
  }

  /// Rota pendente — consumida pelo router na primeira oportunidade
  String? _pendingRoute;
  String? consumePendingRoute() {
    final r = _pendingRoute;
    _pendingRoute = null;
    return r;
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
