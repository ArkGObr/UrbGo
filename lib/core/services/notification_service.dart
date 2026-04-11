import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Canal Android de alta importância
const _kAndroidChannel = AndroidNotificationChannel(
  'urbgo_channel',
  'UrbGo',
  description: 'Notificações de corridas e saldo',
  importance: Importance.high,
  playSound: true,
);

/// Handler de background — deve ser top-level (fora de qualquer classe)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase já está inicializado no main.dart antes deste handler ser registrado
  debugPrint('[FCM Background] ${message.messageId}');
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
    _motoboyActivePath  = motoboyActive;
  }

  Future<void> initialize() async {
    // 1. Solicitar permissão
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Inicializar notificações locais
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // pedido feito pelo FCM acima
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // 3. Criar canal Android
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kAndroidChannel);

    // 4. Exibir notificação local enquanto app está aberto (foreground)
    FirebaseMessaging.onMessage.listen(_showLocal);

    // 5. Navegar quando usuário toca na notificação com app em background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteNavigation);

    // 6. Verificar notificação que abriu o app do estado terminated
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleRemoteNavigation(initial);
  }

  /// Salva o FCM token do usuário no banco
  Future<void> saveToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;

      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token}).eq('id', userId);

      // Atualizar quando token for renovado pelo Firebase
      _fcm.onTokenRefresh.listen((newToken) async {
        try {
          await Supabase.instance.client
              .from('users')
              .update({'fcm_token': newToken}).eq('id', userId);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[FCM] Erro ao salvar token: $e');
    }
  }

  /// Remove o token ao fazer logout (evita notificações indevidas)
  Future<void> clearToken(String userId) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': null}).eq('id', userId);
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
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF99eb09),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['deliveryId'],
    );
  }

  void _onLocalTap(NotificationResponse response) {
    _navigate(response.payload, response.payload);
  }

  void _handleRemoteNavigation(RemoteMessage message) {
    final deliveryId = message.data['deliveryId'] as String?;
    final role       = message.data['role'] as String?;
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

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());
