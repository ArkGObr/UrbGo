class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role; // 'client' | 'motoboy'
  final String status;
  final bool isReleased;
  final String? blockReason;
  final String? avatarUrl;
  final String? description;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    required this.status,
    this.isReleased = true,
    this.blockReason,
    this.avatarUrl,
    this.description,
  });

  bool get isClient => role == 'client';
  bool get isMotoboy => role == 'motoboy';
  bool get isActive => status == 'active';
  bool get canAccessMotoboyApp => !isMotoboy || (isActive && isReleased);

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String?,
    role: json['role'] as String,
    status: json['status'] as String? ?? 'active',
    isReleased: json['is_released'] as bool? ?? true,
    blockReason: json['block_reason'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    description: json['description'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'role': role,
    'status': status,
    'is_released': isReleased,
    if (blockReason != null) 'block_reason': blockReason,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    if (description != null) 'description': description,
  };

  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    String? status,
    bool? isReleased,
    String? blockReason,
    String? avatarUrl,
    String? description,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      isReleased: isReleased ?? this.isReleased,
      blockReason: blockReason ?? this.blockReason,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      description: description ?? this.description,
    );
  }
}
