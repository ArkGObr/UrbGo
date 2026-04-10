class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role; // 'client' | 'motoboy'
  final String status;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    required this.status,
  });

  bool get isClient  => role == 'client';
  bool get isMotoboy => role == 'motoboy';

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id:     json['id'] as String,
        name:   json['name'] as String,
        phone:  json['phone'] as String? ?? '',
        email:  json['email'] as String?,
        role:   json['role'] as String,
        status: json['status'] as String? ?? 'active',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'role': role,
        'status': status,
      };
}
