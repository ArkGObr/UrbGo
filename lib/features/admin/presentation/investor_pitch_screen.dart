import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../domain/analytics_providers.dart';
import 'widgets/live_events_feed.dart';
import 'widgets/live_metric_counter.dart';
import 'widgets/pitch_map_painter.dart';

class InvestorPitchScreen extends ConsumerStatefulWidget {
  const InvestorPitchScreen({super.key});

  @override
  ConsumerState<InvestorPitchScreen> createState() =>
      _InvestorPitchScreenState();
}

class _InvestorPitchScreenState extends ConsumerState<InvestorPitchScreen>
    with TickerProviderStateMixin {
  late final AnimationController _counterController;
  late final AnimationController _mapController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _counterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _mapController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(analyticsProvider);
      _counterController
        ..reset()
        ..forward();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _counterController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(analyticsProvider);
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      body: analytics.when(
        data: (data) {
          final points = List.generate(
            max(6, data.recentEvents.length + 2),
            (index) => Offset(
              (index + 1) * (size.width / 8),
              80 + (index.isEven ? size.height * 0.25 : size.height * 0.55),
            ),
          );
          final body = Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _mapController,
                  builder: (_, __) => CustomPaint(
                    painter: PitchMapPainter(
                      points: points,
                      pulse: _mapController.value * pi * 2,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('Sair do modo pitch'),
                        ),
                      ),
                      const Spacer(),
                      LiveMetricCounter(
                        value: data.summary.totalMinutesSaved.round(),
                        animation: CurvedAnimation(
                          parent: _counterController,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _PitchMetric(
                            label: 'Corridas com IA ativa agora',
                            value: '${data.activeAiRides}',
                          ),
                          _PitchMetric(
                            label: 'Taxa de desvios aceitos',
                            value:
                                '${data.summary.rerouteAcceptanceRate.toStringAsFixed(0)}%',
                          ),
                          _PitchMetric(
                            label: 'Economia média por corrida',
                            value:
                                '${(data.summary.totalMinutesSaved / (data.summary.totalRides == 0 ? 1 : data.summary.totalRides)).toStringAsFixed(1)} min',
                          ),
                          _PitchMetric(
                            label: 'Precisão do ETA',
                            value:
                                '${data.summary.aiAccuracyPercent.toStringAsFixed(0)}%',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      LiveEventsFeed(events: data.recentEvents),
                    ],
                  ),
                ),
              ),
            ],
          );
          return size.width > size.height
              ? body
              : SingleChildScrollView(
                  child: SizedBox(height: size.height, child: body),
                );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Erro ao carregar pitch: $error',
            style: AppTypography.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _PitchMetric extends StatelessWidget {
  final String label;
  final String value;

  const _PitchMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: AppTypography.numericLarge.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
