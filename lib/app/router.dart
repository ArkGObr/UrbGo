import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/domain/auth_provider.dart';
import '../features/auth/domain/user_model.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/check_email_screen.dart';
import '../features/client/presentation/client_home_screen.dart';
import '../features/client/presentation/create_delivery_screen.dart';
import '../features/client/presentation/tracking_screen.dart';
import '../features/motoboy/presentation/motoboy_home_screen.dart';
import '../features/motoboy/presentation/available_runs_screen.dart';
import '../features/motoboy/presentation/active_run_screen.dart';
import '../features/motoboy/presentation/wallet_screen.dart';
import 'page_transitions.dart';

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

      // ── 2. Telas de autenticação (login / register / check-email) ─────────
      final onLoginRegister =
          path == '/login' || path == '/register' || path == '/check-email';

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
      // ── Auth (fade through) ────────────────────────────────
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) => fadeThroughTransition(
          key: state.pageKey,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => fadeThroughTransition(
          key: state.pageKey,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) => slideUpFadeTransition(
          key: state.pageKey,
          child: const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: '/check-email',
        pageBuilder: (_, state) => fadeThroughTransition(
          key: state.pageKey,
          child: const CheckEmailScreen(),
        ),
      ),

      // ── Cliente ────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => child,
        routes: [
          GoRoute(
            path: '/client/home',
            pageBuilder: (_, state) => fadeThroughTransition(
              key: state.pageKey,
              child: const ClientHomeScreen(),
            ),
          ),
          GoRoute(
            path: '/client/create',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const CreateDeliveryScreen(),
            ),
          ),
          GoRoute(
            path: '/client/tracking/:id',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: TrackingScreen(
                deliveryId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),

      // ── Motoboy ────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => child,
        routes: [
          GoRoute(
            path: '/motoboy/home',
            pageBuilder: (_, state) => fadeThroughTransition(
              key: state.pageKey,
              child: const MotoboyHomeScreen(),
            ),
          ),
          GoRoute(
            path: '/motoboy/runs',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const AvailableRunsScreen(),
            ),
          ),
          GoRoute(
            path: '/motoboy/active/:id',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: ActiveRunScreen(
                deliveryId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/motoboy/wallet',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const WalletScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
