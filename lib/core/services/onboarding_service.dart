import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingSeenKey = 'onboarding_seen_v1';

class OnboardingService {
  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingSeenKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingSeenKey, true);
  }
}

final onboardingServiceProvider = Provider<OnboardingService>(
  (ref) => OnboardingService(),
);

final onboardingSeenProvider = FutureProvider<bool>((ref) async {
  return ref.read(onboardingServiceProvider).hasSeenOnboarding();
});
