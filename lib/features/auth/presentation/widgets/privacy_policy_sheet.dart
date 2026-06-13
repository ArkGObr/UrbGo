import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';

class PrivacyPolicySheet extends StatelessWidget {
  const PrivacyPolicySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PrivacyPolicySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl3,
                ),
                children: const [
                  _TitleBlock(),
                  SizedBox(height: AppSpacing.xl),
                  _Section(
                    title: '1. Dados que coletamos',
                    body:
                        'Coletamos dados de cadastro, contato, documentos enviados, enderecos, informacoes de entregas, meios de pagamento, localizacao em tempo real durante operacoes e registros tecnicos do dispositivo para viabilizar o servico com seguranca.',
                  ),
                  _Section(
                    title: '2. Como usamos os dados',
                    body:
                        'Usamos essas informacoes para criar contas, intermediar corridas, conectar clientes e entregadores, calcular rotas e valores, enviar avisos operacionais, prevenir fraudes, atender exigencias legais e melhorar a qualidade da plataforma.',
                  ),
                  _Section(
                    title: '3. Compartilhamento',
                    body:
                        'Compartilhamos apenas o necessario para executar a entrega, processar pagamentos, enviar notificacoes, armazenar documentos e cumprir obrigacoes legais. Dados nao sao vendidos a terceiros.',
                  ),
                  _Section(
                    title: '4. Localizacao e notificacoes',
                    body:
                        'A localizacao do entregador pode ser usada em segundo plano quando ele estiver online ou com corrida ativa. Notificacoes e alertas sonoros sao utilizados para avisos importantes de novas corridas, status e operacao.',
                  ),
                  _Section(
                    title: '5. Retencao e seguranca',
                    body:
                        'Mantemos dados pelo tempo necessario para a operacao, suporte, auditoria e cumprimento legal. Adotamos controles tecnicos e organizacionais para reduzir acesso indevido, perda ou uso inadequado das informacoes.',
                  ),
                  _Section(
                    title: '6. Seus direitos',
                    body:
                        'Voce pode solicitar acesso, correcao, atualizacao ou exclusao de dados pessoais, observadas as obrigacoes legais e regulatórias aplicaveis. Tambem pode pedir informacoes sobre tratamento e compartilhamento.',
                  ),
                  _Section(
                    title: '7. Contato e versao',
                    body:
                        'Ao continuar com o cadastro, voce declara ciencia desta Politica de Privacidade na versao 2026-06-11. Dúvidas e solicitacoes podem ser tratadas pelos canais oficiais da operacao ArkGo.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Politica de Privacidade', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Resumo objetivo sobre coleta, uso, compartilhamento e protecao dos dados tratados no app.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}
