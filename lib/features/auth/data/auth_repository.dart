import 'package:supabase_flutter/supabase_flutter.dart';
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
  }) async {
    final response = await _db.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: 'urbgo://login-callback',
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
      },
    );

    if (response.user == null) {
      throw Exception('Erro ao criar conta. Tente novamente.');
    }

    final userId = response.user!.id;
    final session = response.session;

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
        final data = await _db.from('users').select().eq('id', userId).maybeSingle();

        if (data != null) {
          // Já lidamos com isso de forma global no novo Trigger, mas mantemos update pra redundancia de safety.
          final updateData = <String, dynamic>{
            'phone': phone,
            'name': name,
          };
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
        throw Exception('Conta foi criada, porém os detalhes extras podem não ter sido salvos perfeitamente: $e');
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

  Future<UserModel> _fetchUser(String id) async {
    final data =
        await _db.from('users').select().eq('id', id).single();
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
