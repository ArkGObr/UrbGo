import '../../../core/constants/vehicle_categories.dart';

enum MotoboyApprovalStatus {
  pendingDocuments,
  pendingReview,
  approved,
  rejected,
}

extension MotoboyApprovalStatusX on MotoboyApprovalStatus {
  String get id => switch (this) {
    MotoboyApprovalStatus.pendingDocuments => 'pending_documents',
    MotoboyApprovalStatus.pendingReview => 'pending_review',
    MotoboyApprovalStatus.approved => 'approved',
    MotoboyApprovalStatus.rejected => 'rejected',
  };

  String get label => switch (this) {
    MotoboyApprovalStatus.pendingDocuments => 'Cadastro incompleto',
    MotoboyApprovalStatus.pendingReview => 'Em análise',
    MotoboyApprovalStatus.approved => 'Aprovado',
    MotoboyApprovalStatus.rejected => 'Reprovado',
  };

  String get summary => switch (this) {
    MotoboyApprovalStatus.pendingDocuments =>
      'Envie todos os documentos obrigatórios para liberar o perfil.',
    MotoboyApprovalStatus.pendingReview =>
      'Seu cadastro está aguardando conferência da equipe.',
    MotoboyApprovalStatus.approved =>
      'Perfil liberado para ficar online e aceitar corridas.',
    MotoboyApprovalStatus.rejected =>
      'Há pendências no cadastro. Revise os documentos enviados.',
  };

  static MotoboyApprovalStatus fromId(String? value) {
    return MotoboyApprovalStatus.values.firstWhere(
      (status) => status.id == value,
      orElse: () => MotoboyApprovalStatus.pendingDocuments,
    );
  }
}

bool driverCategoryNeedsPlate(VehicleCategory category) {
  return category != VehicleCategory.bike;
}

bool driverCategoryNeedsVehicleDocument(VehicleCategory category) {
  return category != VehicleCategory.bike;
}

bool driverCategoryNeedsCnh(VehicleCategory category) {
  return category != VehicleCategory.bike;
}

bool driverCategoryNeedsAdditionalPermit(VehicleCategory category) {
  return category == VehicleCategory.mototaxi ||
      category == VehicleCategory.van ||
      category == VehicleCategory.truck;
}

String driverAdditionalPermitLabel(VehicleCategory category) {
  return switch (category) {
    VehicleCategory.mototaxi => 'Licença para transporte de passageiros',
    VehicleCategory.van ||
    VehicleCategory.truck => 'Licença/registro para transporte de carga',
    _ => 'Documento complementar',
  };
}

List<String> missingDriverRegistrationItems({
  required VehicleCategory category,
  required String cpf,
  required String vehiclePlate,
  required String vehicleModel,
  required String vehicleYear,
  required String cnhNumber,
  required String cnhCategory,
  required DateTime? cnhExpirationDate,
  required String addressZipCode,
  required String addressNumber,
  required String addressLabel,
  required bool hasIdentityDocument,
  required bool hasSelfieWithDocument,
  required bool hasVehicleDocument,
  required bool hasAdditionalPermit,
}) {
  final missing = <String>[];

  if (addressZipCode.trim().length < 8 || addressLabel.trim().isEmpty) {
    missing.add('CEP do endereço');
  }

  if (addressNumber.trim().isEmpty) {
    missing.add('número do endereço');
  }

  if (!hasIdentityDocument) {
    missing.add('documento de identificação');
  }

  if (!hasSelfieWithDocument) {
    missing.add('selfie para reconhecimento facial');
  }

  if (driverCategoryNeedsVehicleDocument(category) && !hasVehicleDocument) {
    missing.add('documento do veículo em PDF');
  }

  if (driverCategoryNeedsAdditionalPermit(category) && !hasAdditionalPermit) {
    missing.add(driverAdditionalPermitLabel(category).toLowerCase());
  }

  return missing;
}
