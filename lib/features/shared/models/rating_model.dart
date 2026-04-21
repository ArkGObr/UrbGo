class RatingModel {
  final String id;
  final String deliveryId;
  final String clientId;
  final String motoboyId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const RatingModel({
    required this.id,
    required this.deliveryId,
    required this.clientId,
    required this.motoboyId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory RatingModel.fromJson(Map<String, dynamic> json) => RatingModel(
        id: json['id'] as String,
        deliveryId: json['delivery_id'] as String,
        clientId: json['client_id'] as String,
        motoboyId: json['motoboy_id'] as String,
        rating: json['rating'] as int,
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
