import 'package:supabase_flutter/supabase_flutter.dart';

class PricingRule {
  final String name;
  final String ruleType;
  final String days;
  final int startHour;
  final int endHour;
  final Map<String, dynamic> multipliers;

  const PricingRule({
    required this.name,
    required this.ruleType,
    required this.days,
    required this.startHour,
    required this.endHour,
    required this.multipliers,
  });

  factory PricingRule.fromJson(Map<String, dynamic> json) {
    return PricingRule(
      name: json['name'] as String,
      ruleType: json['rule_type'] as String,
      days: json['days'] as String? ?? '',
      startHour: json['start_hour'] as int? ?? 0,
      endHour: json['end_hour'] as int? ?? 24,
      multipliers: Map<String, dynamic>.from(
        json['multipliers'] as Map? ?? const {},
      ),
    );
  }

  bool appliesTo(DateTime rideTime) {
    if (!_matchesDate(rideTime)) return false;
    return _matchesHour(rideTime.hour);
  }

  bool _matchesDate(DateTime rideTime) {
    if (ruleType == 'specific_date') {
      final date = _formatDate(rideTime);
      return days == date;
    }

    if (ruleType == 'weekly') {
      final weekday = (rideTime.weekday % 7).toString();
      return days
          .split(',')
          .map((day) => day.trim())
          .where((day) => day.isNotEmpty)
          .contains(weekday);
    }

    return false;
  }

  bool _matchesHour(int hour) {
    if (startHour == endHour) return true;
    if (startHour < endHour) {
      return hour >= startHour && hour < endHour;
    }
    return hour >= startHour || hour < endHour;
  }

  String _formatDate(DateTime rideTime) {
    final month = rideTime.month.toString().padLeft(2, '0');
    final day = rideTime.day.toString().padLeft(2, '0');
    return '${rideTime.year}-$month-$day';
  }

  double multiplierFor(String vehicleCategoryKey) {
    final raw =
        multipliers[vehicleCategoryKey] ??
        multipliers[vehicleCategoryKey.toUpperCase()];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0.0;
    return 0.0;
  }
}

class SurgeInfo {
  final double multiplier;
  final String? ruleName;
  final String? description;

  const SurgeInfo({required this.multiplier, this.ruleName, this.description});

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

  List<PricingRule> _cachedRules = const [];
  DateTime? _cacheExpiry;

  Future<List<PricingRule>> _fetchRules() async {
    if (_cachedRules.isNotEmpty &&
        _cacheExpiry != null &&
        DateTime.now().isBefore(_cacheExpiry!)) {
      return _cachedRules;
    }

    final data = await Supabase.instance.client
        .from('pricing_rules')
        .select('name, rule_type, days, start_hour, end_hour, multipliers')
        .eq('is_active', true);

    _cachedRules = (data as List)
        .map((item) => PricingRule.fromJson(item as Map<String, dynamic>))
        .toList();
    _cacheExpiry = DateTime.now().add(const Duration(minutes: 30));
    return _cachedRules;
  }

  Future<SurgeInfo> getCurrentSurge({
    required String vehicleCategoryKey,
    DateTime? at,
  }) async {
    final rideTime = at ?? DateTime.now();
    try {
      final rules = await _fetchRules();

      PricingRule? activeRule;
      double activeMultiplier = 0.0;

      for (final rule in rules) {
        if (!rule.appliesTo(rideTime)) continue;
        final multiplier = rule.multiplierFor(vehicleCategoryKey);
        if (multiplier > activeMultiplier) {
          activeMultiplier = multiplier;
          activeRule = rule;
        }
      }

      if (activeRule != null && activeMultiplier > 0) {
        return SurgeInfo(
          multiplier: 1.0 + activeMultiplier,
          ruleName: activeRule.name,
          description: 'Adicional configurado no painel administrativo.',
        );
      }
    } catch (_) {
      // Mantém preço normal se a leitura remota falhar.
    }

    return const SurgeInfo(multiplier: 1.0);
  }
}
