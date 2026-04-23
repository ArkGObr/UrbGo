import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

class ConnectivityService {
  static final _connectivity = Connectivity();

  static Stream<List<ConnectivityResult>> get stream =>
      _connectivity.onConnectivityChanged;

  static Future<bool> isConnected() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  static Future<bool> ensureConnected(
    BuildContext context, {
    String message = 'Você está sem internet no momento.',
  }) async {
    final connected = await isConnected();
    if (connected || !context.mounted) return connected;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
}

/// Banner animado que aparece quando o dispositivo fica offline.
/// Adicionar no topo do Scaffold de qualquer tela.
class OfflineBanner extends StatelessWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: ConnectivityService.stream,
      builder: (context, snap) {
        final offline =
            snap.hasData &&
            snap.data!.every((r) => r == ConnectivityResult.none);

        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: offline ? 44 : 0,
              color: AppColors.error,
              child: offline
                  ? Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Sem conexão. Algumas ações podem falhar.',
                            style: AppTypography.labelSmall.copyWith(
                              color: Colors.white,
                              fontSize: 11,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
            if (offline)
              Container(
                width: double.infinity,
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  'Você ainda pode navegar, mas criar pedidos, aceitar corridas e atualizar dados depende de internet.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

final connectivityProvider = StreamProvider<bool>((ref) {
  return ConnectivityService.stream.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});
