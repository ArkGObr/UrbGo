import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Splash Logo / Image
          Center(
            child: Image.asset(
              'assets/arkgo-logo.png',
              width: 200,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          // Loading indicator at the bottom
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 64.0),
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
