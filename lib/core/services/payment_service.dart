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

  /// Cria cobrança PIX no Asaas (via Edge Function)
  Future<PixChargeResult> createPixCharge({
    required String motoboyId,
    required double amount,
  }) async {
    final response = await _dio.post(
      '/create-pix-charge',
      data: {'motoboyId': motoboyId, 'amount': amount},
      options: Options(headers: _authHeaders),
    );
    return PixChargeResult.fromJson(response.data);
  }

  /// Simula recarga (apenas em dev)
  Future<SimulateRechargeResult> simulateRecharge({
    required String motoboyId,
    required double amount,
  }) async {
    final response = await _dio.post(
      '/simulate-recharge',
      data: {
        'motoboyId': motoboyId,
        'amount': amount,
      },
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
