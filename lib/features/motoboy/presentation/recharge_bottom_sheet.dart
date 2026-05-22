import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_toast.dart';
import '../../shared/widgets/primary_button.dart';
import '../domain/motoboy_providers.dart';

final _paymentServiceProvider = Provider<PaymentService>(
  (ref) => PaymentService(),
);

class RechargeBottomSheet extends ConsumerStatefulWidget {
  final String motoboyId;

  const RechargeBottomSheet({super.key, required this.motoboyId});

  @override
  ConsumerState<RechargeBottomSheet> createState() =>
      _RechargeBottomSheetState();
}

class _RechargeBottomSheetState extends ConsumerState<RechargeBottomSheet> {
  // Etapas: 0 = selecionar valor, 1 = QR Code, 2 = confirmado
  int _step = 0;
  double _selectedAmount = 0;
  double _resolvedAmount = 0;
  final _customAmountCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isPolling = false;

  // Dados do QR Code
  PixChargeResult? _pixResult;
  Timer? _expirationTimer;
  Timer? _autoCheckTimer;
  int _remainingSeconds = 30 * 60; // 30 min

  final List<double> _presetAmounts = [20, 50, 100, 200];

  @override
  void dispose() {
    _customAmountCtrl.dispose();
    _expirationTimer?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateCharge() async {
    final amount = _selectedAmount > 0
        ? _selectedAmount
        : double.tryParse(_customAmountCtrl.text.replaceAll(',', '.').trim()) ??
              0;
    _resolvedAmount = amount;

    if (amount < 20) {
      AppToast.show(
        context,
        title: 'Valor mínimo não atingido',
        subtitle: 'O valor mínimo de recarga é R\$ 20,00',
        type: AppToastType.warning,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final paymentService = ref.read(_paymentServiceProvider);

      if (paymentService.isSimulationMode) {
        await paymentService.simulateRecharge(
          motoboyId: widget.motoboyId,
          amount: amount,
        );
        ref.invalidate(motoboyStreamProvider);
        ref.invalidate(transactionsProvider);
        if (mounted) {
          setState(() => _step = 2);
          AppToast.show(
            context,
            title: 'Saldo recarregado!',
            subtitle:
                '${CurrencyFormatter.format(amount)} adicionado à sua carteira',
            type: AppToastType.success,
            duration: const Duration(seconds: 5),
          );
        }
      } else {
        // Modo produção: gera QR Code real
        final result = await paymentService.createPixCharge(
          motoboyId: widget.motoboyId,
          amount: amount,
        );
        if (mounted) {
          setState(() {
            _pixResult = result;
            _step = 1;
            _startExpirationTimer();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          title: 'Erro ao gerar cobrança',
          subtitle: e.toString(),
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startExpirationTimer() {
    _expirationTimer?.cancel();
    _remainingSeconds = 30 * 60;
    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
          if (_remainingSeconds <= 0) {
            timer.cancel();
            _autoCheckTimer?.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });

    // Polling automático a cada 15s — não depende do botão "Já paguei"
    _autoCheckTimer?.cancel();
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || _step != 1 || _isPolling) return;
      await _checkOnce();
    });
  }

  /// Uma única verificação sem bloquear o estado de polling manual
  Future<void> _checkOnce() async {
    if (_pixResult == null) return;
    try {
      final result = await ref
          .read(_paymentServiceProvider)
          .checkPixStatus(rechargeId: _pixResult!.rechargeId);
      if (result.isConfirmed && mounted) {
        _autoCheckTimer?.cancel();
        ref.invalidate(motoboyStreamProvider);
        ref.invalidate(transactionsProvider);
        setState(() => _step = 2);
        AppToast.show(
          context,
          title: 'PIX confirmado!',
          subtitle:
              '${CurrencyFormatter.format(_resolvedAmount)} adicionado à sua carteira',
          type: AppToastType.success,
          duration: const Duration(seconds: 5),
        );
      }
    } catch (_) {
      // Silencioso — próxima tentativa em 15s
    }
  }

  String get _formattedTime {
    final min = _remainingSeconds ~/ 60;
    final sec = _remainingSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // Botão "Já paguei" — tenta 6 vezes a cada 5s (30s no total)
  Future<void> _pollForConfirmation() async {
    if (_pixResult == null) return;
    setState(() => _isPolling = true);

    for (int i = 0; i < 6; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;

      try {
        final result = await ref
            .read(_paymentServiceProvider)
            .checkPixStatus(rechargeId: _pixResult!.rechargeId);

        if (result.isConfirmed) {
          _autoCheckTimer?.cancel();
          ref.invalidate(motoboyStreamProvider);
          ref.invalidate(transactionsProvider);
          if (mounted) {
            setState(() {
              _step = 2;
              _isPolling = false;
            });
            AppToast.show(
              context,
              title: 'PIX confirmado!',
              subtitle:
                  '${CurrencyFormatter.format(_resolvedAmount)} adicionado à sua carteira',
              type: AppToastType.success,
              duration: const Duration(seconds: 5),
            );
          }
          return;
        }
      } catch (_) {
        // Continua tentando
      }
    }

    if (mounted) {
      setState(() => _isPolling = false);
      AppToast.show(
        context,
        title: 'Pagamento não detectado ainda',
        subtitle: 'Aguarde — verificamos automaticamente a cada 15 segundos',
        type: AppToastType.warning,
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final bottomPad = bottomInset > 0 ? bottomInset : safeBottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(height: AppSpacing.xl2),

              if (_step == 0) _buildAmountStep(),
              if (_step == 1) _buildQrCodeStep(),
              if (_step == 2) _buildConfirmedStep(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 0: Selecionar valor ───────────────────────────────
  Widget _buildAmountStep() {
    return Column(
      children: [
        // Ícone
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Icon(
            Icons.pix_rounded,
            color: AppColors.primary,
            size: 32,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Recarga via PIX', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Selecione o valor para recarregar',
          style: AppTypography.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl3),

        // Chips de valor pré-definido
        Row(
          children: _presetAmounts.map((amount) {
            final isSelected = _selectedAmount == amount;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _selectedAmount = amount;
                  _customAmountCtrl.clear();
                }),
                child: Container(
                  margin: EdgeInsets.only(
                    right: amount == _presetAmounts.last ? 0 : AppSpacing.sm,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryDeep
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceBorder,
                      width: isSelected ? 1.5 : 0.8,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'R\$${amount.toInt()}',
                      style: AppTypography.labelMedium.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Campo personalizado
        Row(
          children: [
            Text('ou digite um valor:', style: AppTypography.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _customAmountCtrl,
          keyboardType: TextInputType.number,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          onChanged: (_) => setState(() => _selectedAmount = 0),
          decoration: const InputDecoration(
            hintText: '0,00',
            prefixText: 'R\$ ',
          ),
        ),
        const SizedBox(height: AppSpacing.xl3),

        // Botão gerar
        PrimaryButton(
          label: 'Gerar QR Code PIX',
          onPressed: _isLoading ? null : _generateCharge,
          isLoading: _isLoading,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  // ── Step 1: QR Code ────────────────────────────────────────
  Widget _buildQrCodeStep() {
    final pix = _pixResult!;

    return Column(
      children: [
        Text('Pague com PIX', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Escaneie o QR Code ou use o copia e cola',
          style: AppTypography.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl2),

        // QR Code
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: pix.qrCodeBase64 != null
              ? Image.memory(
                  base64Decode(pix.qrCodeBase64!),
                  fit: BoxFit.contain,
                )
              : Center(
                  child: Text(
                    'QR Code indisponível\nUse o copia e cola abaixo',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.xl2),

        // Timer de expiração
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.timer_outlined,
                color: AppColors.warning,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Expira em $_formattedTime',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl2),

        // Copia e cola
        Text('Copia e Cola:', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: pix.pixCode));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Código PIX copiado!',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.surface,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    pix.pixCode,
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.copy_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl3),

        Text(
          'Após o pagamento, seu saldo será\natualizado automaticamente',
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl2),

        // Botão verificar
        PrimaryButton(
          label: _isPolling ? 'Verificando...' : 'Já paguei, verificar saldo',
          onPressed: _isPolling ? null : _pollForConfirmation,
          isLoading: _isPolling,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  // ── Step 2: Confirmado ─────────────────────────────────────
  Widget _buildConfirmedStep() {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xl2),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: AppColors.primary,
            size: 48,
          ),
        ),
        const SizedBox(height: AppSpacing.xl2),
        Text('Recarga Confirmada!', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Seu saldo foi atualizado com sucesso',
          style: AppTypography.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl3),
        PrimaryButton(
          label: 'Fechar',
          onPressed: () {
            ref.invalidate(motoboyStreamProvider);
            ref.invalidate(transactionsProvider);
            Navigator.pop(context);
          },
        ),
        const SizedBox(height: AppSpacing.xl2),
      ],
    );
  }
}
