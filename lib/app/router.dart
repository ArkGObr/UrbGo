import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/domain/auth_provider.dart';
import '../features/auth/domain/user_model.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/client/presentation/client_home_screen.dart';
import '../features/client/presentation/create_delivery_screen.dart';
import '../features/client/presentation/tracking_screen.dart';
import '../features/motoboy/presentation/motoboy_home_screen.dart';
import '../features/motoboy/presentation/available_runs_screen.dart';
import '../features/motoboy/presentation/active_run_screen.dart';
import '../features/motoboy/presentation/wallet_screen.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen<AsyncValue<UserModel?>>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final _routerNotifierProvider = Provider<_RouterNotifier>(
  (ref) => _RouterNotifier(ref),
);

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authAsync = ref.read(authNotifierProvider);
      final path = state.matchedLocation;

      // ── 1. Estado inicial (carregando sessão) ──────────────
      // Fica na splash enquanto resolve
      if (authAsync.isLoading) {
        // Se já passou da splash (ex.: signIn em andamento numa tela interna),
        // não redirecionar — só deixa o loading indicator da tela atual atuar
        if (path == '/splash') return null;
        return null;
      }

      final user = authAsync.valueOrNull;

      // ── 2. Telas de autenticação (login / register) ─────────
      final onLoginRegister =
          path == '/login' || path == '/register';

      // ── 3. Na splash após resolver: redirecionar ────────────
      if (path == '/splash') {
        return user == null ? '/login' : (user.isClient ? '/client/home' : '/motoboy/home');
      }

      // ── 4. Sem sessão fora das telas de auth → login ────────
      if (user == null && !onLoginRegister) return '/login';

      // ── 5. Com sessão nas telas de auth → home correta ──────
      if (user != null && onLoginRegister) {
        return user.isClient ? '/client/home' : '/motoboy/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash',   builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login',    builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (_, __, child) => child,
        routes: [
          GoRoute(path: '/client/home',   builder: (_, __) => const ClientHomeScreen()),
          GoRoute(path: '/client/create', builder: (_, __) => const CreateDeliveryScreen()),
          GoRoute(
            path: '/client/tracking/:id',
            builder: (_, state) =>
                TrackingScreen(deliveryId: state.pathParameters['id']!),
          ),
        ],
      ),
      ShellRoute(
        builder: (_, __, child) => child,
        routes: [
          GoRoute(path: '/motoboy/home',   builder: (_, __) => const MotoboyHomeScreen()),
          GoRoute(path: '/motoboy/runs',   builder: (_, __) => const AvailableRunsScreen()),
          GoRoute(
            path: '/motoboy/active/:id',
            builder: (_, state) =>
                ActiveRunScreen(deliveryId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/motoboy/wallet', builder: (_, __) => const WalletScreen()),
        ],
      ),
    ],
  );
});
