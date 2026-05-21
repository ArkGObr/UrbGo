import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../domain/analytics_providers.dart';

class AnalyticsDashboardScreen extends ConsumerWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);
    final notifier = ref.read(analyticsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analytics ArkGO'),
        backgroundColor: AppColors.background,
      ),
      body: Padding(
        padding: AppSpacing.screenPaddingFull,
        child: analytics.when(
          data: (data) => ListView(
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final period in const ['7d', '30d', '90d'])
                    ChoiceChip(
                      label: Text(period),
                      selected: false,
                      onSelected: (_) => notifier.setPeriod(period),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.45,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  MetricCard(
                    title: 'Minutos Economizados',
                    value: data.summary.totalMinutesSaved.toStringAsFixed(0),
                    subtitle: 'pela IA este periodo',
                  ),
                  MetricCard(
                    title: 'Corridas Analisadas',
                    value: '${data.summary.totalRides}',
                    subtitle: 'impactadas pelo motor inteligente',
                  ),
                  MetricCard(
                    title: 'Taxa de Aceitacao',
                    value:
                        '${data.summary.rerouteAcceptanceRate.toStringAsFixed(0)}%',
                    subtitle: 'desvios aceitos',
                  ),
                  MetricCard(
                    title: 'Custo por Corrida',
                    value: CurrencyFormatter.format(
                      (data.costAnalysis['costPerRideBRL'] as num?)
                              ?.toDouble() ??
                          0,
                    ),
                    subtitle: 'inteligencia de trafego',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TimeSeriesChart(points: data.timeSeries),
              const SizedBox(height: AppSpacing.lg),
              CorridorBarChart(items: data.topCorridors),
              const SizedBox(height: AppSpacing.lg),
              RoiTable(costAnalysis: data.costAnalysis),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () {},
                child: const Text('Exportar Relatorio'),
              ),
            ],
          ),
          loading: () => const _DashboardSkeleton(),
          error: (error, _) =>
              Center(child: Text('Erro ao carregar analytics: $error')),
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.labelMedium),
          const Spacer(),
          Text(value, style: AppTypography.numericLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: AppTypography.bodySmall),
        ],
      ),
    );
  }
}

class TimeSeriesChart extends StatelessWidget {
  final List<Map<String, dynamic>> points;

  const TimeSeriesChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Minutos economizados', style: AppTypography.h4),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 220,
            child: _SparklineChart(
              values: [
                for (final point in points)
                  (point['minutesSaved'] as num?)?.toDouble() ?? 0,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CorridorBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const CorridorBarChart({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top corredores', style: AppTypography.h4),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final item in items)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _SimpleBar(
                        label: (item['origin_area'] as String?) ?? 'Corredor',
                        value:
                            ((item['avgDelay'] as num?)?.toDouble() ?? 0) / 60,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RoiTable extends StatelessWidget {
  final Map<String, dynamic> costAnalysis;

  const RoiTable({super.key, required this.costAnalysis});

  @override
  Widget build(BuildContext context) {
    final cost = (costAnalysis['estimatedApiCostBRL'] as num?)?.toDouble() ?? 0;
    final savings =
        (costAnalysis['savingsPerRideBRL'] as num?)?.toDouble() ?? 0;
    final roi = cost == 0 ? 0 : ((savings - cost) / cost) * 100;
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ROI da IA', style: AppTypography.h4),
          const SizedBox(height: AppSpacing.md),
          _row('Custo total das APIs', CurrencyFormatter.format(cost)),
          _row('Valor economizado (tempo)', CurrencyFormatter.format(savings)),
          _row('ROI', '${roi.toStringAsFixed(1)}%'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: List.generate(
        5,
        (_) => Container(
          height: 120,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}

class _SparklineChart extends StatelessWidget {
  final List<double> values;

  const _SparklineChart({required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(values),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;

  _SparklinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue).abs() < 0.001
        ? 1.0
        : maxValue - minValue;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? 0.0
          : (i / (values.length - 1)) * size.width;
      final y =
          size.height -
          ((values[i] - minValue) / range) * (size.height - 24) -
          12;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _SimpleBar extends StatelessWidget {
  final String label;
  final double value;

  const _SimpleBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final normalized = value <= 0 ? 0.1 : value.clamp(0.1, 12.0) / 12.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall,
        ),
      ],
    );
  }
}
