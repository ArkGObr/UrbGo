import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/notification_service.dart';
import '../data/auth_repository.dart';
import 'user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    // Escuta eventos de logout do Supabase Auth
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedOut) {
        state = const AsyncValue.data(null);
      } else if (data.event == AuthChangeEvent.signedIn) {
        final user = await ref.read(authRepositoryProvider).getSessionUser();
        state = AsyncValue.data(user);
        if (user != null) _initNotifications(user.id);
      }
    });

    final delay = Future.delayed(const Duration(seconds: 2));
    final user = await ref.read(authRepositoryProvider).getSessionUser();
    await delay;

    // Inicializa FCM e salva token para o usuário logado
    if (user != null) {
      _initNotifications(user.id);
    }

    return user;
  }

  Future<void> signUp({
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
    state = const AsyncValue.loading();

    final result = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .signUp(
            email: email,
            password: password,
            name: name,
            phone: phone,
            role: role,
            clientType: clientType,
            document: document,
            vehiclePlate: vehiclePlate,
            vehicleCategory: vehicleCategory,
            vehicleModel: vehicleModel,
            vehicleYear: vehicleYear,
            motoboyCpf: motoboyCpf,
            rgNumber: rgNumber,
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
          ),
    );

    if (result.hasError) {
      state = AsyncValue.error(result.error!, result.stackTrace!);
    } else {
      state = result;
      if (result.value != null) _initNotifications(result.value!.id);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncValue.loading();

    final result = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password),
    );

    if (result.hasError) {
      state = AsyncValue.error(result.error!, result.stackTrace!);
    } else {
      state = result;
      if (result.value != null) _initNotifications(result.value!.id);
    }
  }

  Future<void> resetPassword(String email) async {
    await ref.read(authRepositoryProvider).resetPassword(email);
  }

  Future<void> signOut() async {
    final userId = state.valueOrNull?.id;
    await ref.read(authRepositoryProvider).signOut();
    if (userId != null) {
      await ref.read(notificationServiceProvider).clearToken(userId);
    }
    state = const AsyncValue.data(null);
  }

  void _initNotifications(String userId) {
    final notif = ref.read(notificationServiceProvider);
    notif.initialize();
    notif.saveToken(userId);
    notif.setNavigationCallbacks(
      clientTracking: (id) => '/client/tracking/$id',
      motoboyActive: (id) => '/motoboy/active/$id',
    );
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(
  AuthNotifier.new,
);
