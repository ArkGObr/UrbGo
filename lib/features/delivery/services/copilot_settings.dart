import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CopilotSettings {
  final bool audioEnabled;
  final bool notificationsEnabled;
  final int minimumTimeSavingMinutes;

  const CopilotSettings({
    this.audioEnabled = true,
    this.notificationsEnabled = true,
    this.minimumTimeSavingMinutes = 2,
  });

  CopilotSettings copyWith({
    bool? audioEnabled,
    bool? notificationsEnabled,
    int? minimumTimeSavingMinutes,
  }) {
    return CopilotSettings(
      audioEnabled: audioEnabled ?? this.audioEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      minimumTimeSavingMinutes:
          minimumTimeSavingMinutes ?? this.minimumTimeSavingMinutes,
    );
  }
}

class CopilotSettingsNotifier extends StateNotifier<CopilotSettings> {
  CopilotSettingsNotifier() : super(const CopilotSettings()) {
    _load();
  }

  static const _audioKey = 'copilot_audio_enabled';
  static const _notificationsKey = 'copilot_notifications_enabled';
  static const _minimumKey = 'copilot_minimum_time_saving';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = CopilotSettings(
      audioEnabled: prefs.getBool(_audioKey) ?? true,
      notificationsEnabled: prefs.getBool(_notificationsKey) ?? true,
      minimumTimeSavingMinutes: prefs.getInt(_minimumKey) ?? 2,
    );
  }

  Future<void> update(CopilotSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioKey, settings.audioEnabled);
    await prefs.setBool(_notificationsKey, settings.notificationsEnabled);
    await prefs.setInt(_minimumKey, settings.minimumTimeSavingMinutes);
  }
}

final copilotSettingsProvider =
    StateNotifierProvider<CopilotSettingsNotifier, CopilotSettings>(
      (ref) => CopilotSettingsNotifier(),
    );
