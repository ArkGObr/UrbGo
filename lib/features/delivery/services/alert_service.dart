import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../data/models/route_result.dart';
import 'copilot_settings.dart';

final alertServiceProvider = Provider<AlertService>((ref) {
  return AlertService(ref);
});

class AlertService {
  AlertService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  Future<void> sendRerouteAlert(
    String message,
    RouteResult alternativeRoute,
    int timeSavedMin,
  ) async {
    await initialize();
    final settings = _ref.read(copilotSettingsProvider);
    if (settings.notificationsEnabled) {
      await _local.show(
        7001,
        'Desvio sugerido pelo ArkGO',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'copilot_alerts',
            'Copiloto ArkGO',
            channelDescription: 'Alertas proativos de desvio',
            importance: Importance.high,
            priority: Priority.high,
            actions: [
              AndroidNotificationAction('accept_reroute', 'Aceitar desvio'),
              AndroidNotificationAction('ignore_reroute', 'Ignorar'),
            ],
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: alternativeRoute.sourceLabel,
      );
    }

    if (settings.audioEnabled) {
      // TODO: conectar TTS nativo quando o pacote de voz estiver instalado no projeto.
      await _local.show(
        7002,
        'Alerta por áudio pendente',
        'Desvio sugerido economiza $timeSavedMin minutos.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'copilot_audio_fallback',
            'Copiloto ArkGO - fallback',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    }
  }
}
