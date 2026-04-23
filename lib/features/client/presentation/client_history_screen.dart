import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/vehicle_badge.dart';
import '../domain/client_providers.dart';
import '../domain/delivery_model.dart';
import 'widgets/rating_bottom_sheet.dart';

class ClientHistoryScreen extends ConsumerStatefulWidget {
  const ClientHistoryScreen({super.key});

  @override
  ConsumerState<ClientHistoryScreen> createState() =>
      _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends ConsumerState<ClientHistoryScreen> {
  static const _pageSize = 20;

  final List<DeliveryModel> _deliveries = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasMore = true;
      _deliveries.clear();
    });
    await _loadPage(reset: true);
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLoading || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _loadPage();
  }

  Future<void> _loadPage({bool reset = false}) async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
      return;
    }

    try {
      final page = await ref
          .read(deliveryRepositoryProvider)
          .getClientHistoryPage(
            clientId: user.id,
            offset: reset ? 0 : _deliveries.length,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _deliveries
            ..clear()
            ..addAll(page);
        } else {
          _deliveries.addAll(page);
        }
        _hasMore = page.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _rate(DeliveryModel delivery) async {
    await RatingBottomSheet.show(context, ref, delivery);
    if (!mounted) return;
    ref.invalidate(clientRatingsProvider);
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final ratingsAsync = ref.watch(clientRatingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Histórico de Entregas', style: AppTypography.h3),
        backgroundColor: AppColors.surface,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.surfaceBorder),
        ),
      ),
      body: _buildBody(ratingsAsync.valueOrNull ?? {}),
    );
  }

  Widget _buildBody(Map<String, int> ratings) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && _deliveries.isEmpty) {
      return ErrorState(
        message: 'Erro ao carregar histórico',
        onRetry: _loadInitial,
      );
    }

    if (_deliveries.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'Nenhuma entrega ainda',
        subtitle: 'Seu histórico de entregas concluídas aparecerá aqui.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(clientRatingsProvider);
        await _loadInitial();
      },
      color: AppColors.primary,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 200) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: _deliveries.length + (_isLoadingMore || _hasMore ? 1 : 0),
          separatorBuilder: (_, index) => index >= _deliveries.length - 1
              ? const SizedBox.shrink()
              : const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) {
            if (i >= _deliveries.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: _isLoadingMore
                      ? const CircularProgressIndicator(
                          color: AppColors.primary,
                        )
                      : Text(
                          'Role para carregar mais',
                          style: AppTypography.bodySmall,
                        ),
                ),
              );
            }

            final d = _deliveries[i];
            final userRating = ratings[d.id];
            return _HistoryCard(
              delivery: d,
              userRating: userRating,
              onRate:
                  d.status == DeliveryStatus.completed &&
                      userRating == null &&
                      d.motoboyId != null
                  ? () => _rate(d)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final DeliveryModel delivery;
  final int? userRating;
  final VoidCallback? onRate;

  static const _ratingLabels = [
    '',
    'Muito ruim',
    'Ruim',
    'Regular',
    'Bom',
    'Excelente',
  ];

  const _HistoryCard({required this.delivery, this.userRating, this.onRate});

  @override
  Widget build(BuildContext context) {
    final rating = userRating;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: delivery.status.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              _StatusBadge(status: delivery.status),
                              VehicleBadge(category: delivery.vehicleCategory),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          CurrencyFormatter.format(delivery.value),
                          style: AppTypography.numericMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AddressRow(
                      icon: Icons.radio_button_on_rounded,
                      iconColor: AppColors.primary,
                      address: delivery.pickupAddress,
                    ),
                    if (delivery.extraStopAddress != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 9),
                        child: Container(
                          width: 1.5,
                          height: 14,
                          color: AppColors.surfaceBorder,
                        ),
                      ),
                      _AddressRow(
                        icon: Icons.add_location_alt_rounded,
                        iconColor: const Color(0xFFFF9800),
                        address: delivery.extraStopAddress!,
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(left: 9),
                      child: Container(
                        width: 1.5,
                        height: 14,
                        color: AppColors.surfaceBorder,
                      ),
                    ),
                    _AddressRow(
                      icon: Icons.location_on_rounded,
                      iconColor: AppColors.error,
                      address: delivery.deliveryAddress,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        if (delivery.motoboyName != null) ...[
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              delivery.motoboyName!,
                              style: AppTypography.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Text(
                          _formatDate(delivery.createdAt),
                          style: AppTypography.bodySmall,
                        ),
                      ],
                    ),
                    if (delivery.status == DeliveryStatus.completed) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(color: AppColors.surfaceBorder, height: 1),
                      const SizedBox(height: AppSpacing.sm),
                      if (rating != null)
                        Row(
                          children: [
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 18,
                                color: i < rating
                                    ? const Color(0xFFFFC107)
                                    : AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              _ratingLabels[rating],
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        )
                      else if (onRate != null)
                        GestureDetector(
                          onTap: onRate,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_border_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'Avaliar entregador',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min atrás';
    if (diff.inHours < 24) return '${diff.inHours}h atrás';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  final DeliveryStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: status.color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            status.label,
            style: AppTypography.labelSmall.copyWith(
              color: status.color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            address,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
