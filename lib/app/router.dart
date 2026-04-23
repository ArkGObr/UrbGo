import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/domain/auth_provider.dart';
import '../features/auth/domain/user_model.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/check_email_screen.dart';
import '../features/auth/presentation/onboarding_screen.dart';
import '../features/client/presentation/client_home_screen.dart';
import '../features/client/presentation/client_history_screen.dart';
import '../features/client/presentation/create_delivery_screen.dart';
import '../features/client/presentation/tracking_screen.dart';
import '../features/client/presentation/client_profile_screen.dart';
import '../features/client/presentation/chat_screen.dart';
import '../features/motoboy/presentation/motoboy_home_screen.dart';
import '../features/motoboy/presentation/available_runs_screen.dart';
import '../features/motoboy/presentation/active_run_screen.dart';
import '../features/motoboy/presentation/wallet_screen.dart';
import '../features/motoboy/presentation/motoboy_profile_screen.dart';
import '../features/motoboy/presentation/run_history_screen.dart';
import '../core/services/onboarding_service.dart';
import '../core/constants/vehicle_categories.dart';
import 'page_transitions.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen<AsyncValue<UserModel?>>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
    ref.listen<AsyncValue<bool>>(
      onboardingSeenProvider,
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
      final onboardingAsync = ref.read(onboardingSeenProvider);
      final path = state.matchedLocation;

      // ── 1. Estado inicial (carregando sessão) ──────────────
      // Fica na splash enquanto resolve
      if (authAsync.isLoading) {
        // Se já passou da splash (ex.: signIn em andamento numa tela interna),
        // não redirecionar — só deixa o loading indicator da tela atual atuar
        if (path == '/splash') return null;
        return null;
      }

      if (onboardingAsync.isLoading) return null;

      final user = authAsync.valueOrNull;
      final hasSeenOnboarding = onboardingAsync.valueOrNull ?? false;

      // ── 2. Telas de autenticação (login / register / check-email) ─────────
      final onLoginRegister =
          path == '/login' || path == '/register' || path == '/check-email';
      final onOnboarding = path == '/onboarding';

      if (!hasSeenOnboarding && path != '/splash' && !onOnboarding) {
        return '/onboarding';
      }

      if (hasSeenOnboarding && onOnboarding) {
        return user == null
            ? '/login'
            : (user.isClient ? '/client/home' : '/motoboy/home');
      }

      // ── 3. Na splash após resolver: redirecionar ────────────
      if (path == '/splash') {
        if (!hasSeenOnboarding) return '/onboarding';
        return user == null
            ? '/login'
            : (user.isClient ? '/client/home' : '/motoboy/home');
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
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, state) => fadeThroughTransition(
          key: state.pageKey,
          child: const OnboardingScreen(),
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
              child: CreateDeliveryScreen(
                initialCategory: state.extra as VehicleCategoryInfo?,
              ),
            ),
          ),
          GoRoute(
            path: '/client/tracking/:id',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: TrackingScreen(deliveryId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/delivery/:id',
            redirect: (_, state) =>
                '/client/tracking/${state.pathParameters['id']!}',
          ),
          GoRoute(
            path: '/client/profile',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const ClientProfileScreen(),
            ),
          ),
          GoRoute(
            path: '/client/history',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const ClientHistoryScreen(),
            ),
          ),
          GoRoute(
            path: '/client/chat/:id',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: ChatScreen(
                deliveryId: state.pathParameters['id']!,
                role: 'client',
                otherPartyName:
                    state.uri.queryParameters['name'] ?? 'Entregador',
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
              child: ActiveRunScreen(deliveryId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/run/:id',
            redirect: (_, state) =>
                '/motoboy/active/${state.pathParameters['id']!}',
          ),
          GoRoute(
            path: '/motoboy/wallet',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const WalletScreen(),
            ),
          ),
          GoRoute(
            path: '/motoboy/history',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const RunHistoryScreen(),
            ),
          ),
          GoRoute(
            path: '/motoboy/profile',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: const MotoboyProfileScreen(),
            ),
          ),
          GoRoute(
            path: '/motoboy/chat/:id',
            pageBuilder: (_, state) => slideUpFadeTransition(
              key: state.pageKey,
              child: ChatScreen(
                deliveryId: state.pathParameters['id']!,
                role: 'motoboy',
                otherPartyName: state.uri.queryParameters['name'] ?? 'Cliente',
              ),
            ),
          ),
          GoRoute(
            path: '/chat/:id',
            redirect: (_, state) {
              final user = ref.read(authNotifierProvider).valueOrNull;
              final id = state.pathParameters['id']!;
              final name = state.uri.queryParameters['name'];
              final role = state.uri.queryParameters['role'];
              if (user == null) return '/login';
              if (user.isClient || role == 'client') {
                return '/client/chat/$id${name != null ? '?name=$name' : ''}';
              }
              return '/motoboy/chat/$id${name != null ? '?name=$name' : ''}';
            },
          ),
        ],
      ),
    ],
  );
});
