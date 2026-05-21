import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/vehicle_categories.dart';
import '../../motoboy/domain/driver_registration_rules.dart';
import '../domain/user_model.dart';

class AuthRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role,
    String? clientType,
    String? document,
    String? vehiclePlate,
    String? vehicleCategory,
    String? vehicleModel,
    int? vehicleYear,
    String? motoboyCpf,
    String? rgNumber,
    String? cnhNumber,
    String? cnhCategory,
    DateTime? cnhExpirationDate,
    String? addressZipCode,
    String? addressNumber,
    String? addressComplement,
    String? addressLabel,
    File? identityDocumentFile,
    File? selfieWithDocumentFile,
    File? cnhPhotoFile,
    File? vehicleDocumentFile,
    File? additionalPermitFile,
  }) async {
    final selectedVehicleCategory = vehicleCategory ?? 'motoboy';

    final response = await _db.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: 'arkgo://login-callback',
      data: {
        'name': name,
        'phone': phone,
        'role': role,
        if (clientType != null) 'client_type': clientType,
        if (document != null) 'document': document,
        if (vehiclePlate != null) 'vehicle_plate': vehiclePlate,
        if (vehicleCategory != null) 'vehicle_category': vehicleCategory,
        if (vehicleModel != null) 'vehicle_model': vehicleModel,
        if (vehicleYear != null) 'vehicle_year': vehicleYear,
        if (motoboyCpf != null) 'cpf': motoboyCpf,
        if (rgNumber != null) 'rg_number': rgNumber,
        if (cnhNumber != null) 'cnh_number': cnhNumber,
        if (cnhCategory != null) 'cnh_category': cnhCategory,
        if (cnhExpirationDate != null)
          'cnh_expiration_date': cnhExpirationDate.toIso8601String(),
      },
    );

    if (response.user == null) {
      throw Exception('Erro ao criar conta. Tente novamente.');
    }

    final userId = response.user!.id;
    final session = response.session;

    if (role == 'motoboy' && session != null) {
      final category = VehicleCategoryExtension.fromId(selectedVehicleCategory);
      await _saveMotoboyRegistration(
        userId: userId,
        category: category,
        cpf: motoboyCpf,
        rgNumber: rgNumber,
        vehiclePlate: vehiclePlate,
        vehicleCategory: selectedVehicleCategory,
        vehicleModel: vehicleModel,
        vehicleYear: vehicleYear,
        cnhNumber: cnhNumber,
        cnhCategory: cnhCategory,
        cnhExpirationDate: cnhExpirationDate,
        addressZipCode: addressZipCode,
        addressNumber: addressNumber,
        addressComplement: addressComplement,
        addressLabel: addressLabel,
        identityDocumentFile: identityDocumentFile,
        selfieWithDocumentFile: selfieWithDocumentFile,
        cnhPhotoFile: cnhPhotoFile,
        vehicleDocumentFile: vehicleDocumentFile,
        additionalPermitFile: additionalPermitFile,
      );
    }

    if (session == null) {
      // Confirmação de e-mail ativada no Supabase!
      // Joga flag específica para roteamento
      throw Exception('check_email_flag');
    }

    // Se estiver usando Confirmacao desligada, aguarda o DB sincornizar a sessao validada
    UserModel? user;
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final data = await _db
            .from('users')
            .select()
            .eq('id', userId)
            .maybeSingle();

        if (data != null) {
          // Já lidamos com isso de forma global no novo Trigger, mas mantemos update pra redundancia de safety.
          final updateData = <String, dynamic>{'phone': phone, 'name': name};
          if (clientType != null) updateData['client_type'] = clientType;
          if (document != null) updateData['document'] = document;
          await _db.from('users').update(updateData).eq('id', userId);

          user = await _fetchUser(userId);
          break;
        }
      } catch (_) {
        // Continua retry
      }
    }

    if (user == null) {
      try {
        await _db.from('users').upsert({
          'id': userId,
          'name': name,
          'phone': phone,
          'role': role,
          'status': 'active',
          if (clientType != null) 'client_type': clientType,
          if (document != null) 'document': document,
        });

        user = await _fetchUser(userId);
      } catch (e) {
        throw Exception(
          'Conta foi criada, porém os detalhes extras podem não ter sido salvos perfeitamente: $e',
        );
      }
    }

    return user;
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _db.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.user == null) throw Exception('Credenciais inválidas');
    return _fetchUser(response.user!.id);
  }

  Future<void> signOut() => _db.auth.signOut();

  Future<void> resetPassword(String email) async {
    await _db.auth.resetPasswordForEmail(email);
  }

  Future<void> _saveMotoboyRegistration({
    required String userId,
    required VehicleCategory category,
    String? cpf,
    String? rgNumber,
    String? vehiclePlate,
    String? vehicleCategory,
    String? vehicleModel,
    int? vehicleYear,
    String? cnhNumber,
    String? cnhCategory,
    DateTime? cnhExpirationDate,
    String? addressZipCode,
    String? addressNumber,
    String? addressComplement,
    String? addressLabel,
    File? identityDocumentFile,
    File? selfieWithDocumentFile,
    File? cnhPhotoFile,
    File? vehicleDocumentFile,
    File? additionalPermitFile,
  }) async {
    final identityDocumentUrl = await _uploadDriverDocument(
      userId: userId,
      folder: 'identity',
      file: identityDocumentFile,
    );
    final selfieWithDocumentUrl = await _uploadDriverDocument(
      userId: userId,
      folder: 'selfie',
      file: selfieWithDocumentFile,
    );
    final cnhPhotoUrl = await _uploadDriverDocument(
      userId: userId,
      folder: 'cnh',
      file: cnhPhotoFile,
    );
    final vehicleDocumentUrl = await _uploadDriverDocument(
      userId: userId,
      folder: 'vehicle-document',
      file: vehicleDocumentFile,
    );
    final additionalPermitUrl = await _uploadDriverDocument(
      userId: userId,
      folder: 'additional-permit',
      file: additionalPermitFile,
    );

    final status =
        missingDriverRegistrationItems(
          category: category,
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
          hasIdentityDocument: identityDocumentUrl != null,
          hasSelfieWithDocument: selfieWithDocumentUrl != null,
          hasVehicleDocument: vehicleDocumentUrl != null,
          hasAdditionalPermit: additionalPermitUrl != null,
        ).isEmpty
        ? MotoboyApprovalStatus.pendingReview
        : MotoboyApprovalStatus.pendingDocuments;

    for (int i = 0; i < 10; i++) {
      final exists = await _db
          .from('motoboys')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      if (exists != null) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    await _db.from('motoboys').upsert({
      'id': userId,
      'wallet_balance': 0.0,
      'is_online': false,
      'cpf': cpf,
      'rg_number': rgNumber,
      'vehicle_plate': vehiclePlate,
      'vehicle_category': vehicleCategory,
      'vehicle_model': vehicleModel,
      'vehicle_year': vehicleYear,
      'cnh_number': cnhNumber,
      'cnh_category': cnhCategory,
      'cnh_expiration_date': cnhExpirationDate?.toIso8601String(),
      'address_zip_code': addressZipCode,
      'address_number': addressNumber,
      'address_complement': addressComplement,
      'address_label': addressLabel,
      'identity_document_url': identityDocumentUrl,
      'selfie_with_document_url': selfieWithDocumentUrl,
      'cnh_photo_url': cnhPhotoUrl,
      'vehicle_document_url': vehicleDocumentUrl,
      'additional_permit_url': additionalPermitUrl,
      'approval_status': status.id,
      'rejection_reason': null,
      'documents_submitted_at': status == MotoboyApprovalStatus.pendingReview
          ? DateTime.now().toIso8601String()
          : null,
    });
  }

  Future<String?> _uploadDriverDocument({
    required String userId,
    required String folder,
    required File? file,
  }) async {
    if (file == null) return null;

    final ext = file.path.contains('.') ? file.path.split('.').last : 'jpg';
    final path =
        '$userId/$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _db.storage
        .from('driver-documents')
        .upload(path, file, fileOptions: const FileOptions(upsert: true));

    return path;
  }

  Future<UserModel> _fetchUser(String id) async {
    final data = await _db.from('users').select().eq('id', id).single();
    return UserModel.fromJson(data);
  }

  Future<UserModel?> getSessionUser() async {
    final session = _db.auth.currentSession;
    if (session == null) return null;
    try {
      return await _fetchUser(session.user.id);
    } catch (_) {
      return null;
    }
  }

  Stream<AuthState> get authStateStream => _db.auth.onAuthStateChange;
}
