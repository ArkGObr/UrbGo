import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gerencia subscriptions Realtime com reconexão automática em caso de falha.
class RealtimeManager {
  final SupabaseClient _db = Supabase.instance.client;
  final List<RealtimeChannel> _channels = [];

  /// Cria e registra um canal Realtime com reconexão automática.
  RealtimeChannel subscribe({
    required String channelName,
    required String table,
    required PostgresChangeEvent event,
    String? filterColumn,
    String? filterValue,
    required void Function(PostgresChangePayload) callback,
  }) {
    final filter = filterColumn != null
        ? PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: filterColumn,
            value: filterValue!,
          )
        : null;

    late RealtimeChannel channel;

    void connect() {
      channel = _db
          .channel(channelName)
          .onPostgresChanges(
            event: event,
            schema: 'public',
            table: table,
            filter: filter,
            callback: callback,
          )
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.channelError) {
          debugPrint('[Realtime] Canal "$channelName" caiu ($status). Reconectando em 3s...');
          Future.delayed(const Duration(seconds: 3), () {
            try {
              channel.subscribe();
            } catch (_) {}
          });
        }
      });
    }

    connect();
    _channels.add(channel);
    return channel;
  }

  /// Remove todos os canais registrados.
  Future<void> dispose() async {
    for (final ch in _channels) {
      try {
        await _db.removeChannel(ch);
      } catch (_) {}
    }
    _channels.clear();
  }

  /// Remove um canal específico.
  Future<void> removeChannel(RealtimeChannel channel) async {
    try {
      await _db.removeChannel(channel);
      _channels.remove(channel);
    } catch (_) {}
  }
}
