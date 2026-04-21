import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';

enum AppToastType { success, info, warning, error }

extension _ToastTypeX on AppToastType {
  Color get color => switch (this) {
        AppToastType.success => AppColors.success,
        AppToastType.info    => AppColors.info,
        AppToastType.warning => AppColors.warning,
        AppToastType.error   => AppColors.error,
      };

  IconData get icon => switch (this) {
        AppToastType.success => Icons.check_circle_rounded,
        AppToastType.info    => Icons.info_rounded,
        AppToastType.warning => Icons.warning_amber_rounded,
        AppToastType.error   => Icons.error_rounded,
      };
}

/// Toast overlay animado exibido no topo da tela.
///
/// Uso:
/// ```dart
/// AppToast.show(
///   context,
///   title: 'Entregador a caminho!',
///   subtitle: 'Seu pedido foi aceito',
///   type: AppToastType.info,
/// );
/// ```
class AppToast {
  // Fila de entradas ativas
  static final List<_ToastEntry> _queue = [];

  static void show(
    BuildContext context, {
    required String title,
    String? subtitle,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!context.mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    late _ToastEntry ref;

    entry = OverlayEntry(
      builder: (_) => _AppToastWidget(
        title: title,
        subtitle: subtitle,
        type: type,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        stackIndex: _queue.indexOf(ref),
        onDismiss: () {
          entry.remove();
          _queue.remove(ref);
          // Atualiza índice dos toasts restantes
          for (final e in _queue) {
            e.entry.markNeedsBuild();
          }
        },
      ),
    );

    ref = _ToastEntry(entry: entry);
    _queue.add(ref);
    overlay.insert(entry);
  }

  /// Remove todos os toasts visíveis imediatamente.
  static void dismissAll() {
    for (final e in List.of(_queue)) {
      e.entry.remove();
    }
    _queue.clear();
  }
}

class _ToastEntry {
  final OverlayEntry entry;
  _ToastEntry({required this.entry});
}

// ── Widget interno ─────────────────────────────────────────────

class _AppToastWidget extends StatefulWidget {
  final String title;
  final String? subtitle;
  final AppToastType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final int stackIndex;
  final VoidCallback onDismiss;

  const _AppToastWidget({
    required this.title,
    this.subtitle,
    required this.type,
    required this.duration,
    this.actionLabel,
    this.onAction,
    required this.stackIndex,
    required this.onDismiss,
  });

  @override
  State<_AppToastWidget> createState() => _AppToastWidgetState();
}

class _AppToastWidgetState extends State<_AppToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _autoTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();

    _autoTimer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _autoTimer?.cancel();
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    const itemHeight = 80.0;
    final topOffset = topPad + 12 + (widget.stackIndex * (itemHeight + 8));
    final color = widget.type.color;

    return Positioned(
      top: topOffset,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              onHorizontalDragEnd: (_) => _dismiss(),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: color.withValues(alpha: 0.45),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                    const BoxShadow(
                      color: Colors.black54,
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Conteúdo ──────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ícone colorido
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(widget.type.icon, color: color, size: 21),
                            ),
                            const SizedBox(width: AppSpacing.md),

                            // Textos
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: AppTypography.labelLarge.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (widget.subtitle != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.subtitle!,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (widget.actionLabel != null) ...[
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () {
                                        widget.onAction?.call();
                                        _dismiss();
                                      },
                                      child: Text(
                                        widget.actionLabel!,
                                        style: AppTypography.labelSmall.copyWith(
                                          color: color,
                                          decoration: TextDecoration.underline,
                                          decorationColor: color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),

                            // Botão fechar
                            GestureDetector(
                              onTap: _dismiss,
                              child: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textTertiary,
                                size: 17,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Barra de progresso ────────────────
                      _ProgressBar(
                        duration: widget.duration,
                        color: color,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Barra de progresso animada ─────────────────────────────────

class _ProgressBar extends StatefulWidget {
  final Duration duration;
  final Color color;

  const _ProgressBar({required this.duration, required this.color});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => LinearProgressIndicator(
        value: 1 - _ctrl.value,
        backgroundColor: AppColors.surfaceBorder,
        valueColor: AlwaysStoppedAnimation<Color>(
          widget.color.withValues(alpha: 0.7),
        ),
        minHeight: 2,
      ),
    );
  }
}
