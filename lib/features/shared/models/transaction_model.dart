class TransactionModel {
  final String id;
  final String motoboyId;
  final String? deliveryId;
  final String type; // 'recharge' | 'commission_debit'
  final double amount;
  final double balanceAfter;
  final String? description;
  final DateTime createdAt;

  const TransactionModel({
    required this.id,
    required this.motoboyId,
    this.deliveryId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    required this.createdAt,
  });

  bool get isCredit => type == 'recharge';
  bool get isDebit => type == 'commission_debit';

  String get typeLabel => isCredit ? 'Recarga' : 'Comissão';

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      motoboyId: json['motoboy_id'] as String,
      deliveryId: json['delivery_id'] as String?,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      balanceAfter: (json['balance_after'] as num).toDouble(),
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
