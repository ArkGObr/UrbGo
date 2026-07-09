import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/navigation_launcher_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/chat_repository.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  final String role; // 'client' ou 'motoboy'
  final String otherPartyName;

  const ChatScreen({
    super.key,
    required this.deliveryId,
    required this.role,
    required this.otherPartyName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _repo = ChatRepository();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  RealtimeChannel? _channel;

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _channel = _repo.watchMessages(widget.deliveryId, (msg) {
      if (mounted) {
        setState(() {
          if (_messages.any((m) => m.id == msg.id)) return;
          _messages.add(msg);
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await _repo.getMessages(widget.deliveryId);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar conversa: $e'),
            backgroundColor: AppColors.surface,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user == null) return;

    setState(() => _sending = true);
    try {
      _msgCtrl.clear();
      await _repo.sendMessage(
        deliveryId: widget.deliveryId,
        senderId: user.id,
        senderRole: widget.role,
        content: text,
      );
    } catch (e) {
      if (mounted) {
        _msgCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar: $e'),
            backgroundColor: AppColors.surface,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authNotifierProvider).valueOrNull?.id;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text(widget.otherPartyName, style: AppTypography.h4),
            Text(
              widget.role == 'client' ? 'Entregador' : 'Cliente',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.surfaceBorder),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Nenhuma mensagem ainda',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md + keyboardHeight,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMine = msg.senderId == userId;
                      return _MessageBubble(message: msg, isMine: isMine);
                    },
                  ),
          ),
          _InputBar(controller: _msgCtrl, sending: _sending, onSend: _send),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final uri = NavigationLauncherService.extractFirstUri(message.content);
    final isMapUri = uri != null && NavigationLauncherService.isMapUri(uri);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mensagem copiada'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          margin: EdgeInsets.only(
            bottom: AppSpacing.xs,
            left: isMine ? AppSpacing.xl3 : 0,
            right: isMine ? 0 : AppSpacing.xl3,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isMine ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadius.md),
              topRight: const Radius.circular(AppRadius.md),
              bottomLeft: Radius.circular(isMine ? AppRadius.md : AppRadius.xs),
              bottomRight: Radius.circular(
                isMine ? AppRadius.xs : AppRadius.md,
              ),
            ),
            border: isMine
                ? null
                : Border.all(color: AppColors.surfaceBorder, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.content,
                style: AppTypography.bodyMedium.copyWith(
                  color: isMine ? AppColors.background : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(message.createdAt),
                style: AppTypography.labelSmall.copyWith(
                  color: isMine
                      ? AppColors.background.withValues(alpha: 0.7)
                      : AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              if (uri != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _openUri(context, uri, isMapUri),
                    icon: Icon(
                      isMapUri
                          ? Icons.navigation_rounded
                          : Icons.open_in_new_rounded,
                      size: 14,
                    ),
                    label: Text(isMapUri ? 'Abrir no mapa' : 'Abrir link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isMine
                          ? AppColors.background
                          : AppColors.primary,
                      side: BorderSide(
                        color: isMine
                            ? AppColors.background.withValues(alpha: 0.35)
                            : AppColors.primary.withValues(alpha: 0.35),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                      textStyle: AppTypography.labelSmall,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUri(BuildContext context, Uri uri, bool isMapUri) async {
    final launched = await const NavigationLauncherService().openExternalUri(
      uri,
    );
    if (launched || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isMapUri
              ? 'Nao foi possivel abrir o app de navegacao.'
              : 'Nao foi possivel abrir o link.',
        ),
        backgroundColor: AppColors.surface,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                maxLines: 4,
                minLines: 1,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Mensagem...',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: sending ? null : onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sending ? AppColors.surfaceBorder : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: AppColors.background,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: AppColors.background,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
