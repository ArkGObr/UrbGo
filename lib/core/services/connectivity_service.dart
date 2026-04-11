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
        final offline = snap.hasData &&
            snap.data!.every((r) => r == ConnectivityResult.none);

        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: offline ? 32 : 0,
              color: AppColors.error,
              child: offline
                  ? Center(
                      child: Text(
                        'Sem conexão com a internet',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                    )
                  : null,
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
