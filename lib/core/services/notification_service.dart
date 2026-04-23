import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Canal principal — corridas, status, saldo
const _kAndroidChannel = AndroidNotificationChannel(
  'urbgo_channel',
  'UrbGo',
  description: 'Notificações de corridas e saldo',
  importance: Importance.high,
  playSound: true,
);

// Canal para notificações de re-engajamento (inatividade)
const _kReengagementChannel = AndroidNotificationChannel(
  'urbgo_reengagement',
  'UrbGo — Lembretes',
  description: 'Lembretes para voltar a fazer entregas',
  importance: Importance.defaultImportance,
  playSound: true,
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

  final title = message.data['title'] as String? ?? 'UrbGo';
  final body = message.data['body'] as String? ?? '';
  if (title.isEmpty) return;

  await local.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _kAndroidChannel.id,
        _kAndroidChannel.name,
        channelDescription: _kAndroidChannel.description,
        icon: 'ic_notification',
        color: const Color(0xFF99eb09),
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(presentSound: true),
    ),
    payload: message.data['deliveryId'],
  );
}

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

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
    // 1. Solicitar permissão (iOS + Android 13+)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

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
        android: AndroidNotificationDetails(
          _kAndroidChannel.id,
          _kAndroidChannel.name,
          channelDescription: _kAndroidChannel.description,
          icon: 'ic_notification',
          color: const Color(0xFF99eb09),
          largeIcon: const DrawableResourceAndroidBitmap(
            '@mipmap/launcher_icon',
          ),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
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
        android: AndroidNotificationDetails(
          _kAndroidChannel.id,
          _kAndroidChannel.name,
          channelDescription: _kAndroidChannel.description,
          icon: 'ic_notification',
          color: const Color(0xFF99eb09),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  void _onLocalTap(NotificationResponse response) {
    if (response.actionId != null) {
      _actionStreamController.add(response.actionId!);
    } else {
      _navigate(response.payload, response.payload);
    }
  }

  void _handleRemoteNavigation(RemoteMessage message) {
    final deliveryId = message.data['deliveryId'] as String?;
    final role = message.data['role'] as String?;
    _navigate(deliveryId, role);
  }

  void _navigate(String? deliveryId, String? role) {
    if (deliveryId == null) return;
    // A navegação real usa um NavigatorKey global definido em app.dart
    // As callbacks são injetadas no initialize do app
    if (role == 'motoboy' && _motoboyActivePath != null) {
      _pendingRoute = _motoboyActivePath!(deliveryId);
    } else if (_clientTrackingPath != null) {
      _pendingRoute = _clientTrackingPath!(deliveryId);
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
