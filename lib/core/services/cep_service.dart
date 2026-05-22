import 'dart:convert';
import 'dart:io';

class CepResult {
  final String zipCode;
  final String street;
  final String neighborhood;
  final String city;
  final String state;

  CepResult({
    required this.zipCode,
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
  });

  /// Linha de endereço exibida ao usuário, ex:
  /// "Rua das Flores, Jardim América — São Paulo/SP"
  String get label {
    final parts = <String>[];
    if (street.isNotEmpty) parts.add(street);
    if (neighborhood.isNotEmpty) parts.add(neighborhood);
    final cityState = [city, state].where((s) => s.isNotEmpty).join('/');
    if (cityState.isNotEmpty) parts.add('— $cityState');
    return parts.join(', ');
  }

  factory CepResult.fromJson(Map<String, dynamic> json) {
    return CepResult(
      zipCode: json['cep'] as String? ?? '',
      street: json['logradouro'] as String? ?? '',
      neighborhood: json['bairro'] as String? ?? '',
      city: json['localidade'] as String? ?? '',
      state: json['uf'] as String? ?? '',
    );
  }
}

class CepService {
  /// Busca endereço via ViaCEP. Retorna null se CEP inválido ou não encontrado.
  static Future<CepResult?> lookup(String cep) async {
    final digits = cep.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      final request = await client.getUrl(
        Uri.parse('https://viacep.com.br/ws/$digits/json/'),
      );
      final response = await request.close();

      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      // ViaCEP retorna {"erro": true} para CEP inválido
      if (json['erro'] == true || json['erro'] == 'true') return null;

      return CepResult.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
