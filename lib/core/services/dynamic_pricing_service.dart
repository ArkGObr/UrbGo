import 'package:supabase_flutter/supabase_flutter.dart';

class PeakHoursRule {
  final String name;
  final String? description;
  final double multiplier;
  final int startHour;
  final int endHour;
  final List<int> daysOfWeek;

  const PeakHoursRule({
    required this.name,
    this.description,
    required this.multiplier,
    required this.startHour,
    required this.endHour,
    required this.daysOfWeek,
  });

  factory PeakHoursRule.fromJson(Map<String, dynamic> json) => PeakHoursRule(
        name: json['name'] as String,
        description: json['description'] as String?,
        multiplier: (json['multiplier'] as num).toDouble(),
        startHour: json['start_hour'] as int,
        endHour: json['end_hour'] as int,
        daysOfWeek: List<int>.from(json['days_of_week'] as List),
      );

  bool appliesTo(DateTime dt) {
    final weekday = dt.weekday % 7; // 0=dom, 1=seg ... 6=sab
    final hour = dt.hour;
    if (!daysOfWeek.contains(weekday)) return false;
    if (startHour <= endHour) {
      return hour >= startHour && hour < endHour;
    }
    // Regra que cruza meia-noite (ex: 22h-02h)
    return hour >= startHour || hour < endHour;
  }
}

class SurgeInfo {
  final double multiplier;
  final String? ruleName;
  final String? description;

  const SurgeInfo({
    required this.multiplier,
    this.ruleName,
    this.description,
  });

  bool get isSurge => multiplier > 1.0;
  bool get isDiscount => multiplier < 1.0;

  String get label {
    if (isSurge) {
      final pct = ((multiplier - 1.0) * 100).round();
      return '+$pct%';
    }
    if (isDiscount) {
      final pct = ((1.0 - multiplier) * 100).round();
      return '-$pct%';
    }
    return '';
  }
}

class DynamicPricingService {
  static final DynamicPricingService _instance = DynamicPricingService._();
  DynamicPricingService._();
  factory DynamicPricingService() => _instance;

  List<PeakHoursRule> _cachedRules = [];
  DateTime? _cacheExpiry;

  Future<List<PeakHoursRule>> _fetchRules() async {
    if (_cachedRules.isNotEmpty &&
        _cacheExpiry != null &&
        DateTime.now().isBefore(_cacheExpiry!)) {
      return _cachedRules;
    }
    try {
      final data = await Supabase.instance.client
          .from('peak_hours_rules')
          .select()
          .eq('is_active', true);
      _cachedRules = (data as List).map((e) => PeakHoursRule.fromJson(e as Map<String, dynamic>)).toList();
      _cacheExpiry = DateTime.now().add(const Duration(minutes: 30));
      return _cachedRules;
    } catch (_) {
      // Fallback embutido se o banco estiver indisponível
      return _defaultRules;
    }
  }

  Future<SurgeInfo> getCurrentSurge([DateTime? at]) async {
    final now = at ?? DateTime.now();
    final rules = await _fetchRules();

    // Aplica a regra de maior impacto (não soma, pega o maior multiplicador ativo)
    PeakHoursRule? active;
    for (final rule in rules) {
      if (rule.appliesTo(now)) {
        if (active == null || rule.multiplier > active.multiplier) {
          active = rule;
        }
      }
    }

    if (active == null) return const SurgeInfo(multiplier: 1.0);

    return SurgeInfo(
      multiplier: active.multiplier,
      ruleName: active.name,
      description: active.description,
    );
  }

  /// Regras padrão embutidas como fallback offline
  static const List<PeakHoursRule> _defaultRules = [
    PeakHoursRule(
      name: 'Horário de Almoço',
      multiplier: 1.30,
      startHour: 11,
      endHour: 14,
      daysOfWeek: [1, 2, 3, 4, 5],
    ),
    PeakHoursRule(
      name: 'Horário de Pico Noturno',
      multiplier: 1.40,
      startHour: 17,
      endHour: 21,
      daysOfWeek: [0, 1, 2, 3, 4, 5, 6],
    ),
    PeakHoursRule(
      name: 'Madrugada',
      multiplier: 0.90,
      startHour: 0,
      endHour: 5,
      daysOfWeek: [0, 1, 2, 3, 4, 5, 6],
    ),
    PeakHoursRule(
      name: 'Final de Semana',
      multiplier: 1.20,
      startHour: 9,
      endHour: 22,
      daysOfWeek: [0, 6],
    ),
  ];
}
