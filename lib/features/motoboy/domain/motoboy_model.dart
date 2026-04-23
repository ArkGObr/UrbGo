import '../../../core/constants/vehicle_categories.dart';
import '../../shared/models/motoboy_reputation.dart';

class MotoboyModel {
  final String id;
  final String name;
  final String phone;
  final double walletBalance;
  final bool isOnline;
  final double? currentLat;
  final double? currentLng;
  final String? vehiclePlate;
  final String? cpf;
  final VehicleCategory vehicleCategory;
  final String? vehicleModel;
  final int? vehicleYear;
  final String? avatarUrl;
  final String? description;
  final double avgRating;
  final int totalRatings;

  const MotoboyModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.walletBalance,
    required this.isOnline,
    this.currentLat,
    this.currentLng,
    this.vehiclePlate,
    this.cpf,
    this.vehicleCategory = VehicleCategory.motoboy,
    this.vehicleModel,
    this.vehicleYear,
    this.avatarUrl,
    this.description,
    this.avgRating = 5.0,
    this.totalRatings = 0,
  });

  /// Retorna true se tem saldo suficiente para aceitar a corrida
  bool canAccept(double commission) => walletBalance >= commission;

  factory MotoboyModel.fromJson(Map<String, dynamic> json) {
    final users = json['users'] as Map<String, dynamic>?;

    return MotoboyModel(
      id: json['id'] as String,
      name: users?['name'] as String? ?? '',
      phone: users?['phone'] as String? ?? '',
      walletBalance: (json['wallet_balance'] as num).toDouble(),
      isOnline: json['is_online'] as bool? ?? false,
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLng: (json['current_lng'] as num?)?.toDouble(),
      vehiclePlate: json['vehicle_plate'] as String?,
      cpf: json['cpf'] as String?,
      vehicleCategory: VehicleCategoryExtension.fromId(
        json['vehicle_category'] as String? ?? 'motoboy',
      ),
      vehicleModel: json['vehicle_model'] as String?,
      vehicleYear: json['vehicle_year'] as int?,
      avatarUrl: json['avatar_url'] as String?,
      description: json['description'] as String?,
      avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 5.0,
      totalRatings: json['total_ratings'] as int? ?? 0,
    );
  }

  MotoboyModel copyWith({
    String? id,
    String? name,
    String? phone,
    double? walletBalance,
    bool? isOnline,
    double? currentLat,
    double? currentLng,
    String? vehiclePlate,
    String? cpf,
    VehicleCategory? vehicleCategory,
    String? vehicleModel,
    int? vehicleYear,
    String? avatarUrl,
    String? description,
    double? avgRating,
    int? totalRatings,
  }) {
    return MotoboyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      walletBalance: walletBalance ?? this.walletBalance,
      isOnline: isOnline ?? this.isOnline,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      cpf: cpf ?? this.cpf,
      vehicleCategory: vehicleCategory ?? this.vehicleCategory,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleYear: vehicleYear ?? this.vehicleYear,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      description: description ?? this.description,
      avgRating: avgRating ?? this.avgRating,
      totalRatings: totalRatings ?? this.totalRatings,
    );
  }

  String get ratingLabel {
    if (totalRatings == 0) return 'Novo';
    return avgRating.toStringAsFixed(1);
  }

  MotoboyReputation get reputation => MotoboyReputation.fromMetrics(
    avgRating: avgRating,
    totalRatings: totalRatings,
  );
}
