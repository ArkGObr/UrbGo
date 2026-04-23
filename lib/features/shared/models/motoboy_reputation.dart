import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

class MotoboyReputation {
  final String level;
  final String label;
  final String summary;
  final Color color;
  final IconData icon;

  const MotoboyReputation({
    required this.level,
    required this.label,
    required this.summary,
    required this.color,
    required this.icon,
  });

  factory MotoboyReputation.fromMetrics({
    required double avgRating,
    required int totalRatings,
  }) {
    if (totalRatings < 5) {
      return const MotoboyReputation(
        level: 'rookie',
        label: 'Novo na plataforma',
        summary: 'Ainda construindo reputacao',
        color: Color(0xFF90A4AE),
        icon: Icons.fiber_new_rounded,
      );
    }
    if (avgRating >= 4.9 && totalRatings >= 80) {
      return const MotoboyReputation(
        level: 'diamond',
        label: 'Diamante',
        summary: 'Top desempenho e confiabilidade',
        color: Color(0xFF4DD0E1),
        icon: Icons.workspace_premium_rounded,
      );
    }
    if (avgRating >= 4.8 && totalRatings >= 40) {
      return const MotoboyReputation(
        level: 'gold',
        label: 'Ouro',
        summary: 'Excelente historico de entregas',
        color: Color(0xFFFFC107),
        icon: Icons.military_tech_rounded,
      );
    }
    if (avgRating >= 4.6 && totalRatings >= 15) {
      return const MotoboyReputation(
        level: 'silver',
        label: 'Prata',
        summary: 'Boa consistencia nas corridas',
        color: Color(0xFFB0BEC5),
        icon: Icons.verified_rounded,
      );
    }
    return const MotoboyReputation(
      level: 'bronze',
      label: 'Bronze',
      summary: 'Reputacao em evolucao',
      color: AppColors.primary,
      icon: Icons.shield_rounded,
    );
  }
}
