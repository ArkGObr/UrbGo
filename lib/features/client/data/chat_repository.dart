import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  final String id;
  final String deliveryId;
  final String senderId;
  final String senderRole;
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.deliveryId,
    required this.senderId,
    required this.senderRole,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        deliveryId: json['delivery_id'] as String,
        senderId: json['sender_id'] as String,
        senderRole: json['sender_role'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ChatRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<ChatMessage>> getMessages(String deliveryId) async {
    final data = await _db
        .from('delivery_messages')
        .select()
        .eq('delivery_id', deliveryId)
        .order('created_at', ascending: true)
        .limit(100);
    return (data as List).map((e) => ChatMessage.fromJson(e)).toList();
  }

  Future<void> sendMessage({
    required String deliveryId,
    required String senderId,
    required String senderRole,
    required String content,
  }) async {
    await _db.from('delivery_messages').insert({
      'delivery_id': deliveryId,
      'sender_id': senderId,
      'sender_role': senderRole,
      'content': content.trim(),
    });
  }

  RealtimeChannel watchMessages(
    String deliveryId,
    void Function(ChatMessage) onNew,
  ) {
    return _db
        .channel('chat-$deliveryId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'delivery_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'delivery_id',
            value: deliveryId,
          ),
          callback: (payload) => onNew(ChatMessage.fromJson(payload.newRecord)),
        )
        .subscribe();
  }
}
