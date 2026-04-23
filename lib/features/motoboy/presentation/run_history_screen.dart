import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../auth/domain/auth_provider.dart';
import '../../client/domain/delivery_model.dart';
import '../../shared/widgets/delivery_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../domain/motoboy_providers.dart';

class RunHistoryScreen extends ConsumerStatefulWidget {
  const RunHistoryScreen({super.key});

  @override
  ConsumerState<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends ConsumerState<RunHistoryScreen> {
  static const _pageSize = 20;

  final _deliveries = <DeliveryModel>[];
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
      _deliveries.clear();
      _isLoading = true;
      _isLoadingMore = false;
      _hasMore = true;
      _error = null;
    });
    await _loadPage(reset: true);
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
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
          .read(motoboyRepositoryProvider)
          .getRunHistoryPage(
            motoboyId: user.id,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Histórico de Corridas', style: AppTypography.h3),
        backgroundColor: AppColors.surface,
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && _deliveries.isEmpty) {
      return ErrorState(message: _error.toString(), onRetry: _loadInitial);
    }

    if (_deliveries.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'Nenhuma corrida',
        subtitle: 'Você ainda não realizou nenhuma entrega.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
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
              : const SizedBox(height: AppSpacing.md),
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

            final delivery = _deliveries[i];
            return DeliveryCard(delivery: delivery, index: i, onTap: () {});
          },
        ),
      ),
    );
  }
}
