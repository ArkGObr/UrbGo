import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../shared/models/motoboy_reputation.dart';

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
    pending => 'Aguardando entregador',
    accepted => 'Entregador a caminho',
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
  final VehicleCategory vehicleCategory;
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
  final double? motoboyAvgRating;
  final int? motoboyTotalRatings;
  final double? distanceKm;

  // Parada extra (multi-stop simplificado)
  final String? extraStopAddress;
  final double? extraStopLat;
  final double? extraStopLng;

  // Foto de confirmação de entrega
  final String? deliveryPhotoUrl;

  // ── Novos campos por categoria ─────────────────────────────

  // Informações do destinatário
  final String? recipientName;
  final String? recipientPhone;

  // Detalhes do item/carga
  final String? itemDescription;
  final bool isFragile;
  final double? declaredValue;

  // Serviços adicionais
  final int helperCount;
  final bool roundTrip;
  final DateTime? scheduledFor;
  final String? cargoType; // 'furniture' | 'appliances' | 'construction' | 'other'

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
    required this.vehicleCategory,
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
    this.motoboyAvgRating,
    this.motoboyTotalRatings,
    this.distanceKm,
    this.extraStopAddress,
    this.extraStopLat,
    this.extraStopLng,
    this.deliveryPhotoUrl,
    this.recipientName,
    this.recipientPhone,
    this.itemDescription,
    this.isFragile = false,
    this.declaredValue,
    this.helperCount = 0,
    this.roundTrip = false,
    this.scheduledFor,
    this.cargoType,
  });

  factory DeliveryModel.fromJson(Map<String, dynamic> json) {
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
      vehicleCategory: VehicleCategoryExtension.fromId(
        json['vehicle_category'] as String? ?? 'motoboy',
      ),
      status: DeliveryStatus.fromString(json['status'] as String),
      paymentMethod: json['payment_method'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      motoboyName:
          motoboy?['users']?['name'] as String? ?? users?['name'] as String?,
      motoboyPhone:
          motoboy?['users']?['phone'] as String? ?? users?['phone'] as String?,
      motoboyPlate: motoboy?['vehicle_plate'] as String?,
      motoboyLat: motoboy != null
          ? (motoboy['current_lat'] as num?)?.toDouble()
          : null,
      motoboyLng: motoboy != null
          ? (motoboy['current_lng'] as num?)?.toDouble()
          : null,
      motoboyAvgRating: motoboy != null
          ? (motoboy['avg_rating'] as num?)?.toDouble()
          : null,
      motoboyTotalRatings: motoboy != null
          ? motoboy['total_ratings'] as int?
          : null,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      extraStopAddress: json['extra_stop_address'] as String?,
      extraStopLat: (json['extra_stop_lat'] as num?)?.toDouble(),
      extraStopLng: (json['extra_stop_lng'] as num?)?.toDouble(),
      deliveryPhotoUrl: json['delivery_photo_url'] as String?,
      recipientName: json['recipient_name'] as String?,
      recipientPhone: json['recipient_phone'] as String?,
      itemDescription: json['item_description'] as String?,
      isFragile: (json['is_fragile'] as bool?) ?? false,
      declaredValue: (json['declared_value'] as num?)?.toDouble(),
      helperCount: (json['helper_count'] as int?) ?? 0,
      roundTrip: (json['is_round_trip'] as bool?) ?? false,
      scheduledFor: json['scheduled_for'] != null
          ? DateTime.parse(json['scheduled_for'] as String)
          : null,
      cargoType: json['cargo_type'] as String?,
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
    VehicleCategory? vehicleCategory,
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
    double? motoboyAvgRating,
    int? motoboyTotalRatings,
    double? distanceKm,
    String? extraStopAddress,
    double? extraStopLat,
    double? extraStopLng,
    String? deliveryPhotoUrl,
    String? recipientName,
    String? recipientPhone,
    String? itemDescription,
    bool? isFragile,
    double? declaredValue,
    int? helperCount,
    bool? roundTrip,
    DateTime? scheduledFor,
    String? cargoType,
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
      vehicleCategory: vehicleCategory ?? this.vehicleCategory,
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
      motoboyAvgRating: motoboyAvgRating ?? this.motoboyAvgRating,
      motoboyTotalRatings: motoboyTotalRatings ?? this.motoboyTotalRatings,
      distanceKm: distanceKm ?? this.distanceKm,
      extraStopAddress: extraStopAddress ?? this.extraStopAddress,
      extraStopLat: extraStopLat ?? this.extraStopLat,
      extraStopLng: extraStopLng ?? this.extraStopLng,
      deliveryPhotoUrl: deliveryPhotoUrl ?? this.deliveryPhotoUrl,
      recipientName: recipientName ?? this.recipientName,
      recipientPhone: recipientPhone ?? this.recipientPhone,
      itemDescription: itemDescription ?? this.itemDescription,
      isFragile: isFragile ?? this.isFragile,
      declaredValue: declaredValue ?? this.declaredValue,
      helperCount: helperCount ?? this.helperCount,
      roundTrip: roundTrip ?? this.roundTrip,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      cargoType: cargoType ?? this.cargoType,
    );
  }

  String get paymentMethodLabel => switch (paymentMethod) {
    'cash' => 'Dinheiro',
    'pix' => 'PIX',
    _ => paymentMethod,
  };

  IconData get paymentMethodIcon => switch (paymentMethod) {
    'cash' => Icons.money_rounded,
    'pix' => Icons.pix_rounded,
    _ => Icons.payment_rounded,
  };

  double get netEarnings => value - commission;

  MotoboyReputation get motoboyReputation => MotoboyReputation.fromMetrics(
    avgRating: motoboyAvgRating ?? 5.0,
    totalRatings: motoboyTotalRatings ?? 0,
  );

  bool get isMotoTaxi => vehicleCategory == VehicleCategory.mototaxi;
  bool get isRide =>
      vehicleCategory == VehicleCategory.mototaxi ||
      vehicleCategory == VehicleCategory.car;

  /// Labels contextuais por categoria (corrida vs entrega)
  String get statusLabelForCategory => switch (status) {
    DeliveryStatus.pending => isRide ? 'Aguardando motorista' : 'Aguardando entregador',
    DeliveryStatus.accepted => isRide ? 'Motorista a caminho' : 'Entregador a caminho',
    DeliveryStatus.inProgress => isRide ? 'Corrida em andamento' : 'Em rota de entrega',
    DeliveryStatus.completed => isRide ? 'Corrida concluída' : 'Entregue',
    DeliveryStatus.cancelled => 'Cancelado',
  };

  String get pickupLabel => isRide ? 'Origem' : 'Coleta';
  String get deliveryLabel => isRide ? 'Destino' : 'Entrega';
  String get driverLabel => isRide ? 'Motorista' : 'Entregador';
  String get serviceLabel => isRide ? 'Corrida' : 'Entrega';

  String get cargoTypeLabel => switch (cargoType) {
    'furniture' => 'Móveis',
    'appliances' => 'Eletrodomésticos',
    'construction' => 'Material de obra',
    'other' => 'Outros',
    _ => 'Geral',
  };

  String get scheduledForLabel {
    if (scheduledFor == null) return 'Imediato';
    final d = scheduledFor!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'Hoje às $timeStr';
    final tomorrow = today.add(const Duration(days: 1));
    if (day == tomorrow) return 'Amanhã às $timeStr';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às $timeStr';
  }

  bool get canCancel {
    if (status == DeliveryStatus.pending) return true;
    if (status == DeliveryStatus.accepted && acceptedAt != null) {
      return DateTime.now().difference(acceptedAt!).inMinutes < 5;
    }
    return false;
  }

  bool get isCancelWithPenaltyWarning =>
      status == DeliveryStatus.accepted && canCancel;

  bool get isActive =>
      status == DeliveryStatus.pending ||
      status == DeliveryStatus.accepted ||
      status == DeliveryStatus.inProgress;

  bool get isScheduled => scheduledFor != null;
  bool get hasHelpers => helperCount > 0;
}
