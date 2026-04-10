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
  });

  /// Retorna true se tem saldo suficiente para aceitar a corrida
  bool canAccept(double commission) => walletBalance >= commission;

  factory MotoboyModel.fromJson(Map<String, dynamic> json) {
    // O join com users pode vir como sub-objeto
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
    );
  }
}
