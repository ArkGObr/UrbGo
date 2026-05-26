import '../../../core/constants/vehicle_categories.dart';
import '../../shared/models/motoboy_reputation.dart';
import 'driver_registration_rules.dart';

class MotoboyModel {
  final String id;
  final String name;
  final String phone;
  final String userStatus;
  final bool isReleased;
  final double walletBalance;
  final bool isOnline;
  final double? currentLat;
  final double? currentLng;
  final String? vehiclePlate;
  final String? cpf;
  final String? rgNumber;
  final String? cnhNumber;
  final String? cnhCategory;
  final DateTime? cnhExpirationDate;
  final String? addressZipCode;
  final String? addressNumber;
  final String? addressComplement;
  final String? addressLabel;
  final VehicleCategory vehicleCategory;
  final String? vehicleModel;
  final int? vehicleYear;
  final String? identityDocumentUrl;
  final String? selfieWithDocumentUrl;
  final String? cnhPhotoUrl;
  final String? vehicleDocumentUrl;
  final String? additionalPermitUrl;
  final MotoboyApprovalStatus approvalStatus;
  final String? rejectionReason;
  final DateTime? documentsSubmittedAt;
  final DateTime? reviewedAt;
  final String? avatarUrl;
  final String? description;
  final double avgRating;
  final int totalRatings;

  const MotoboyModel({
    required this.id,
    required this.name,
    required this.phone,
    this.userStatus = 'pending',
    this.isReleased = false,
    required this.walletBalance,
    required this.isOnline,
    this.currentLat,
    this.currentLng,
    this.vehiclePlate,
    this.cpf,
    this.rgNumber,
    this.cnhNumber,
    this.cnhCategory,
    this.cnhExpirationDate,
    this.addressZipCode,
    this.addressNumber,
    this.addressComplement,
    this.addressLabel,
    this.vehicleCategory = VehicleCategory.motoboy,
    this.vehicleModel,
    this.vehicleYear,
    this.identityDocumentUrl,
    this.selfieWithDocumentUrl,
    this.cnhPhotoUrl,
    this.vehicleDocumentUrl,
    this.additionalPermitUrl,
    this.approvalStatus = MotoboyApprovalStatus.pendingDocuments,
    this.rejectionReason,
    this.documentsSubmittedAt,
    this.reviewedAt,
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
      userStatus: users?['status'] as String? ?? 'pending',
      isReleased: users?['is_released'] as bool? ?? false,
      walletBalance: (json['wallet_balance'] as num).toDouble(),
      isOnline: json['is_online'] as bool? ?? false,
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLng: (json['current_lng'] as num?)?.toDouble(),
      vehiclePlate: json['vehicle_plate'] as String?,
      cpf: json['cpf'] as String?,
      rgNumber: json['rg_number'] as String?,
      cnhNumber: json['cnh_number'] as String?,
      cnhCategory: json['cnh_category'] as String?,
      cnhExpirationDate: json['cnh_expiration_date'] != null
          ? DateTime.tryParse(json['cnh_expiration_date'] as String)
          : null,
      addressZipCode: json['address_zip_code'] as String?,
      addressNumber: json['address_number'] as String?,
      addressComplement: json['address_complement'] as String?,
      addressLabel: json['address_label'] as String?,
      vehicleCategory: VehicleCategoryExtension.fromId(
        json['vehicle_category'] as String? ?? 'motoboy',
      ),
      vehicleModel: json['vehicle_model'] as String?,
      vehicleYear: json['vehicle_year'] as int?,
      identityDocumentUrl: json['identity_document_url'] as String?,
      selfieWithDocumentUrl: json['selfie_with_document_url'] as String?,
      cnhPhotoUrl: json['cnh_photo_url'] as String?,
      vehicleDocumentUrl: json['vehicle_document_url'] as String?,
      additionalPermitUrl: json['additional_permit_url'] as String?,
      approvalStatus: MotoboyApprovalStatusX.fromId(
        json['approval_status'] as String?,
      ),
      rejectionReason: json['rejection_reason'] as String?,
      documentsSubmittedAt: json['documents_submitted_at'] != null
          ? DateTime.tryParse(json['documents_submitted_at'] as String)
          : null,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'] as String)
          : null,
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
    String? userStatus,
    bool? isReleased,
    double? walletBalance,
    bool? isOnline,
    double? currentLat,
    double? currentLng,
    String? vehiclePlate,
    String? cpf,
    String? rgNumber,
    String? cnhNumber,
    String? cnhCategory,
    DateTime? cnhExpirationDate,
    String? addressZipCode,
    String? addressNumber,
    String? addressComplement,
    String? addressLabel,
    VehicleCategory? vehicleCategory,
    String? vehicleModel,
    int? vehicleYear,
    String? identityDocumentUrl,
    String? selfieWithDocumentUrl,
    String? cnhPhotoUrl,
    String? vehicleDocumentUrl,
    String? additionalPermitUrl,
    MotoboyApprovalStatus? approvalStatus,
    String? rejectionReason,
    DateTime? documentsSubmittedAt,
    DateTime? reviewedAt,
    String? avatarUrl,
    String? description,
    double? avgRating,
    int? totalRatings,
  }) {
    return MotoboyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      userStatus: userStatus ?? this.userStatus,
      isReleased: isReleased ?? this.isReleased,
      walletBalance: walletBalance ?? this.walletBalance,
      isOnline: isOnline ?? this.isOnline,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      cpf: cpf ?? this.cpf,
      rgNumber: rgNumber ?? this.rgNumber,
      cnhNumber: cnhNumber ?? this.cnhNumber,
      cnhCategory: cnhCategory ?? this.cnhCategory,
      cnhExpirationDate: cnhExpirationDate ?? this.cnhExpirationDate,
      addressZipCode: addressZipCode ?? this.addressZipCode,
      addressNumber: addressNumber ?? this.addressNumber,
      addressComplement: addressComplement ?? this.addressComplement,
      addressLabel: addressLabel ?? this.addressLabel,
      vehicleCategory: vehicleCategory ?? this.vehicleCategory,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleYear: vehicleYear ?? this.vehicleYear,
      identityDocumentUrl: identityDocumentUrl ?? this.identityDocumentUrl,
      selfieWithDocumentUrl:
          selfieWithDocumentUrl ?? this.selfieWithDocumentUrl,
      cnhPhotoUrl: cnhPhotoUrl ?? this.cnhPhotoUrl,
      vehicleDocumentUrl: vehicleDocumentUrl ?? this.vehicleDocumentUrl,
      additionalPermitUrl: additionalPermitUrl ?? this.additionalPermitUrl,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      documentsSubmittedAt: documentsSubmittedAt ?? this.documentsSubmittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
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

  bool get isApproved => approvalStatus == MotoboyApprovalStatus.approved;

  bool get canGoOnline => isReleased && userStatus == 'active';

  String get accessStatusLabel {
    if (canGoOnline) return 'Liberado para operar';
    return switch (approvalStatus) {
      MotoboyApprovalStatus.pendingDocuments => 'Cadastro incompleto',
      MotoboyApprovalStatus.pendingReview => 'Aguardando aprovação',
      MotoboyApprovalStatus.rejected => 'Cadastro reprovado',
      MotoboyApprovalStatus.approved => 'Aguardando liberação',
    };
  }

  String get accessStatusSummary {
    if (canGoOnline) {
      return 'Seus documentos foram validados e sua conta está ativa.';
    }
    return switch (approvalStatus) {
      MotoboyApprovalStatus.pendingDocuments =>
        'Envie todos os documentos obrigatórios para entrar na fila de análise.',
      MotoboyApprovalStatus.pendingReview =>
        'Seus documentos foram enviados e estão aguardando análise automática.',
      MotoboyApprovalStatus.rejected =>
        'Houve um problema na análise dos documentos. Revise e envie novamente.',
      MotoboyApprovalStatus.approved =>
        'Seus documentos foram aprovados e a liberação da conta está sendo sincronizada.',
    };
  }

  List<String> get missingRegistrationItems => missingDriverRegistrationItems(
    category: vehicleCategory,
    cpf: cpf ?? '',
    rgNumber: rgNumber ?? '',
    vehiclePlate: vehiclePlate ?? '',
    vehicleModel: vehicleModel ?? '',
    vehicleYear: vehicleYear?.toString() ?? '',
    cnhNumber: cnhNumber ?? '',
    cnhCategory: cnhCategory ?? '',
    cnhExpirationDate: cnhExpirationDate,
    addressZipCode: addressZipCode ?? '',
    addressNumber: addressNumber ?? '',
    addressLabel: addressLabel ?? '',
    hasIdentityDocument: identityDocumentUrl?.isNotEmpty == true,
    hasSelfieWithDocument: selfieWithDocumentUrl?.isNotEmpty == true,
    hasVehicleDocument: vehicleDocumentUrl?.isNotEmpty == true,
    hasAdditionalPermit: additionalPermitUrl?.isNotEmpty == true,
  );
}
