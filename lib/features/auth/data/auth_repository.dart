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
    String? vehiclePlate,
  }) async {
    final response = await _db.auth.signUp(
      email: email,
      password: password,
      data: {'name': name, 'phone': phone, 'role': role},
    );

    if (response.user == null) {
      throw Exception('Erro ao criar conta. Tente novamente.');
    }

    final userId = response.user!.id;

    // Aguarda trigger criar o registro em users (com retry)
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
          // Atualiza phone e name caso o trigger não tenha pego dos metadados
          await _db.from('users').update({
            'phone': phone,
            'name': name,
          }).eq('id', userId);

          // Atualiza placa do motoboy se aplicável
          if (role == 'motoboy' &&
              vehiclePlate != null &&
              vehiclePlate.isNotEmpty) {
            await _db
                .from('motoboys')
                .update({'vehicle_plate': vehiclePlate}).eq('id', userId);
          }

          user = await _fetchUser(userId);
          break;
        }
      } catch (_) {
        // Continua retry
      }
    }

    if (user == null) {
      // Cadastro no Auth funcionou mas trigger falhou.
      // Tenta inserir manualmente na tabela users.
      try {
        await _db.from('users').upsert({
          'id': userId,
          'name': name,
          'phone': phone,
          'role': role,
          'status': 'active',
        });

        if (role == 'motoboy') {
          await _db.from('motoboys').upsert({
            'id': userId,
            'wallet_balance': 0.0,
            'is_online': false,
            if (vehiclePlate != null && vehiclePlate.isNotEmpty)
              'vehicle_plate': vehiclePlate,
          });
        }

        user = await _fetchUser(userId);
      } catch (e) {
        throw Exception(
            'Conta criada, mas erro ao configurar perfil. Tente fazer login.');
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
