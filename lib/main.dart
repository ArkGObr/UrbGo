import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'core/constants/supabase_config.dart';
import 'core/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Supabase Flutter v2 não processa deep links automaticamente.
  // Este handler troca o token quando o app abre via link de confirmação de email.
  _handleDeepLinks();

  FlutterError.onError = (details) {
    debugPrint('[Flutter Error]: ${details.exceptionAsString()}');
  };

  runApp(const ProviderScope(child: ArkGoApp()));
}

void _handleDeepLinks() {
  final appLinks = AppLinks();

  // App aberto do zero via link (estado encerrado)
  appLinks.getInitialLink().then((uri) async {
    if (uri != null) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } catch (_) {}
    }
  });

  // App em foreground/background recebe o link
  appLinks.uriLinkStream.listen((uri) async {
    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
    } catch (_) {}
  });
}
