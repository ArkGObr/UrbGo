import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

enum DeliveryStatus {
  pending,
  accepted,
  inProgress,
  completed,
  cancelled;

  static DeliveryStatus fromString(String s) => switch (s) {
        'pending' => pending,
        'accepted' => accepted,
        'in_progress' => inProgress,
        'completed' => completed,
        _ => cancelled,
      };

  String get dbValue => switch (this) {
        pending => 'pending',
        accepted => 'accepted',
        inProgress => 'in_progress',
        completed => 'completed',
        cancelled => 'cancelled',
      };

  String get label => switch (this) {
        pending => 'Aguardando motoboy',
        accepted => 'Motoboy a caminho',
        inProgress => 'Em rota de entrega',
        completed => 'Entregue',
        cancelled => 'Cancelado',
      };

  Color get color => switch (this) {
        pending => AppColors.statusPending,
        accepted => AppColors.statusAccepted,
        inProgress => AppColors.statusInProgress,
        completed => AppColors.statusCompleted,
        cancelled => AppColors.statusCancelled,
      };

  IconData get icon => switch (this) {
        pending => Icons.schedule_rounded,
        accepted => Icons.two_wheeler_rounded,
        inProgress => Icons.local_shipping_rounded,
        completed => Icons.check_circle_rounded,
        cancelled => Icons.cancel_rounded,
      };
}

class DeliveryModel {
  final String id;
  final String clientId;
  final String? motoboyId;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String deliveryAddress;
  final double deliveryLat;
  final double deliveryLng;
  final double value;
  final double commission;
  final DeliveryStatus status;
  final String paymentMethod;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  // Join com motoboys (opcional)
  final String? motoboyName;
  final String? motoboyPhone;
  final String? motoboyPlate;
  final double? motoboyLat;
  final double? motoboyLng;

  const DeliveryModel({
    required this.id,
    required this.clientId,
    this.motoboyId,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.deliveryAddress,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.value,
    required this.commission,
    required this.status,
    required this.paymentMethod,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
    this.motoboyName,
    this.motoboyPhone,
    this.motoboyPlate,
    this.motoboyLat,
    this.motoboyLng,
  });

  factory DeliveryModel.fromJson(Map<String, dynamic> json) {
    // O join com motoboys pode vir como sub-objeto ou
    // o motoboy_id pode referenciar a tabela users
    final motoboy = json['motoboys'] as Map<String, dynamic>?;
    final users = json['users'] as Map<String, dynamic>?;

    return DeliveryModel(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      motoboyId: json['motoboy_id'] as String?,
      pickupAddress: json['pickup_address'] as String,
      pickupLat: (json['pickup_lat'] as num).toDouble(),
      pickupLng: (json['pickup_lng'] as num).toDouble(),
      deliveryAddress: json['delivery_address'] as String,
      deliveryLat: (json['delivery_lat'] as num).toDouble(),
      deliveryLng: (json['delivery_lng'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
      commission: (json['commission'] as num).toDouble(),
      status: DeliveryStatus.fromString(json['status'] as String),
      paymentMethod: json['payment_method'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      motoboyName: motoboy?['users']?['name'] as String? ??
          users?['name'] as String?,
      motoboyPhone: motoboy?['users']?['phone'] as String? ??
          users?['phone'] as String?,
      motoboyPlate: motoboy?['vehicle_plate'] as String?,
      motoboyLat: motoboy != null
          ? (motoboy['current_lat'] as num?)?.toDouble()
          : null,
      motoboyLng: motoboy != null
          ? (motoboy['current_lng'] as num?)?.toDouble()
          : null,
    );
  }

  DeliveryModel copyWith({
    String? id,
    String? clientId,
    String? motoboyId,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? deliveryAddress,
    double? deliveryLat,
    double? deliveryLng,
    double? value,
    double? commission,
    DeliveryStatus? status,
    String? paymentMethod,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? completedAt,
    String? motoboyName,
    String? motoboyPhone,
    String? motoboyPlate,
    double? motoboyLat,
    double? motoboyLng,
  }) {
    return DeliveryModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      motoboyId: motoboyId ?? this.motoboyId,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryLat: deliveryLat ?? this.deliveryLat,
      deliveryLng: deliveryLng ?? this.deliveryLng,
      value: value ?? this.value,
      commission: commission ?? this.commission,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      completedAt: completedAt ?? this.completedAt,
      motoboyName: motoboyName ?? this.motoboyName,
      motoboyPhone: motoboyPhone ?? this.motoboyPhone,
      motoboyPlate: motoboyPlate ?? this.motoboyPlate,
      motoboyLat: motoboyLat ?? this.motoboyLat,
      motoboyLng: motoboyLng ?? this.motoboyLng,
    );
  }

  String get paymentMethodLabel => switch (paymentMethod) {
        'cash' => 'Dinheiro',
        'pix' => 'PIX',
        'card' => 'Maquininha',
        _ => paymentMethod,
      };

  IconData get paymentMethodIcon => switch (paymentMethod) {
        'cash' => Icons.money_rounded,
        'pix' => Icons.pix_rounded,
        'card' => Icons.credit_card_rounded,
        _ => Icons.payment_rounded,
      };

  bool get canCancel => status == DeliveryStatus.pending;
  bool get isActive =>
      status == DeliveryStatus.pending ||
      status == DeliveryStatus.accepted ||
      status == DeliveryStatus.inProgress;
}
