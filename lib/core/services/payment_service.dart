import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentService {
  late final Dio _dio;

  PaymentService() {
    final supabaseUrl = Supabase.instance.client.rest.url.replaceAll(
      '/rest/v1',
      '',
    );

    _dio = Dio(
      BaseOptions(
        baseUrl: '$supabaseUrl/functions/v1',
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  /// Atualiza o header de autorização com o token mais recente
  Map<String, String> get _authHeaders => {
    'Authorization':
        'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken}',
  };

  /// Cria cobrança PIX via Pagar.me (via Edge Function)
  Future<PixChargeResult> createPixCharge({
    required String motoboyId,
    required double amount,
  }) async {
    try {
      final response = await _dio.post(
        '/create-pix-charge',
        data: {'motoboyId': motoboyId, 'amount': amount},
        options: Options(
          headers: _authHeaders,
          // Não lança exceção em erros HTTP — lemos o corpo e decidimos nós mesmos
          validateStatus: (_) => true,
        ),
      );

      final data = response.data as Map<String, dynamic>;

      if (data.containsKey('error')) {
        throw Exception(data['error'].toString());
      }

      if (data['pixCode'] == null || (data['pixCode'] as String).isEmpty) {
        throw Exception(
          'Pagar.me não retornou o código PIX. '
          'Verifique se o PIX está ativado na conta e se a chave está configurada.',
        );
      }

      return PixChargeResult.fromJson(data);
    } on DioException catch (e) {
      // Tenta extrair mensagem do corpo mesmo em erros de rede/timeout
      final serverMsg = e.response?.data is Map<String, dynamic>
          ? e.response!.data['error']?.toString()
          : null;
      throw Exception(serverMsg ?? 'Falha de conexão com o servidor de pagamentos');
    }
  }

  /// Verifica status do PIX diretamente no Pagar.me e credita saldo se pago
  Future<CheckPixResult> checkPixStatus({required String rechargeId}) async {
    try {
      final response = await _dio.post(
        '/check-pix-status',
        data: {'rechargeId': rechargeId},
        options: Options(
          headers: _authHeaders,
          validateStatus: (_) => true,
        ),
      );
      final data = response.data as Map<String, dynamic>;
      if (data.containsKey('error')) throw Exception(data['error'].toString());
      return CheckPixResult.fromJson(data);
    } on DioException catch (e) {
      final serverMsg = e.response?.data is Map<String, dynamic>
          ? e.response!.data['error']?.toString()
          : null;
      throw Exception(serverMsg ?? 'Falha ao verificar pagamento');
    }
  }

  /// Simula recarga (apenas em dev)
  Future<SimulateRechargeResult> simulateRecharge({
    required String motoboyId,
    required double amount,
  }) async {
    final response = await _dio.post(
      '/simulate-recharge',
      data: {'motoboyId': motoboyId, 'amount': amount},
      options: Options(headers: _authHeaders),
    );
    return SimulateRechargeResult.fromJson(response.data);
  }

  /// Decide qual endpoint usar baseado no modo (debug/release)
  bool get isSimulationMode => kDebugMode;
}

// ── PIX Charge Result ────────────────────────────────────────
class PixChargeResult {
  final String rechargeId;
  final String pixCode;
  final String? qrCodeBase64;
  final DateTime expiresAt;

  PixChargeResult({
    required this.rechargeId,
    required this.pixCode,
    this.qrCodeBase64,
    required this.expiresAt,
  });

  factory PixChargeResult.fromJson(Map<String, dynamic> json) {
    return PixChargeResult(
      rechargeId: json['rechargeId'] as String,
      pixCode: json['pixCode'] as String,
      qrCodeBase64: json['qrCodeBase64'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}

// ── Check PIX Result ─────────────────────────────────────────
class CheckPixResult {
  final String status; // 'pending' | 'confirmed'
  final double? newBalance;

  CheckPixResult({required this.status, this.newBalance});

  bool get isConfirmed => status == 'confirmed';

  factory CheckPixResult.fromJson(Map<String, dynamic> json) {
    return CheckPixResult(
      status: json['status'] as String? ?? 'pending',
      newBalance: json['newBalance'] != null
          ? (json['newBalance'] as num).toDouble()
          : null,
    );
  }
}

// ── Simulate Recharge Result ─────────────────────────────────
class SimulateRechargeResult {
  final bool success;
  final double newBalance;

  SimulateRechargeResult({required this.success, required this.newBalance});

  factory SimulateRechargeResult.fromJson(Map<String, dynamic> json) {
    return SimulateRechargeResult(
      success: json['success'] as bool? ?? false,
      newBalance: (json['newBalance'] as num).toDouble(),
    );
  }
}
