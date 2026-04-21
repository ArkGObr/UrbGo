import 'package:flutter/material.dart';

enum VehicleCategory {
  motoboy,
  car,
  bike,
  mototaxi,
  van,
  truck,
}

class VehicleCategoryInfo {
  final VehicleCategory category;
  final String id;
  final String name;
  final IconData icon;
  final String? assetPath;
  final String description;
  final String capacity;
  final int etaMultiplier;

  const VehicleCategoryInfo({
    required this.category,
    required this.id,
    required this.name,
    required this.icon,
    this.assetPath,
    required this.description,
    required this.capacity,
    required this.etaMultiplier,
  });
}

/// Todas as categorias disponíveis no app
const List<VehicleCategoryInfo> vehicleCategories = [
  VehicleCategoryInfo(
    category: VehicleCategory.motoboy,
    id: 'motoboy',
    name: 'Moto Entregas',
    icon: Icons.two_wheeler_rounded,
    description: 'Entregas rápidas, documentos',
    capacity: 'Até 20 kg',
    etaMultiplier: 100,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.car,
    id: 'car',
    name: 'Carro',
    icon: Icons.directions_car_rounded,
    description: 'Viagens confortáveis',
    capacity: 'Até 4 passageiros',
    etaMultiplier: 115,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.bike,
    id: 'bike',
    name: 'Bike Entregas',
    icon: Icons.pedal_bike_rounded,
    description: 'Entregas curtas e ecológicas',
    capacity: 'Até 5 kg',
    etaMultiplier: 150,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.mototaxi,
    id: 'mototaxi',
    name: 'Moto Táxi',
    icon: Icons.motorcycle_rounded,
    description: 'Transporte de passageiros',
    capacity: '1 passageiro',
    etaMultiplier: 100,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.van,
    id: 'van',
    name: 'Utilitário',
    icon: Icons.airport_shuttle_rounded,
    assetPath: 'assets/utilitario.png',
    description: 'Fiorinos e furgões',
    capacity: 'Até 650 kg',
    etaMultiplier: 130,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.truck,
    id: 'truck',
    name: 'Caminhão',
    icon: Icons.local_shipping_rounded,
    assetPath: 'assets/caminhao.png',
    description: 'Mudanças e móveis pesados',
    capacity: 'Até 4.000 kg',
    etaMultiplier: 160,
  ),
];

extension VehicleCategoryExtension on VehicleCategory {
  VehicleCategoryInfo get info =>
      vehicleCategories.firstWhere((v) => v.category == this);

  static VehicleCategory fromId(String id) {
    var match = vehicleCategories.where((v) => v.id == id);
    if (match.isEmpty) return VehicleCategory.motoboy;
    return match.first.category;
  }
}

// ═══════════════════════════════════════════════════════════════
// Tabela de preços por faixa de KM
// ═══════════════════════════════════════════════════════════════

/// Faixa de preço: de [fromKm] até [toKm] km custa [price] reais.
class _PriceTier {
  final double fromKm;
  final double toKm;
  final double price;
  const _PriceTier(this.fromKm, this.toKm, this.price);
}

/// Tabela de preços — MOTO
/// Baseada na tabela real do sistema (distância em km → valor fixo).
/// Faixas CONTÍGUAS: fromKm inclusive, toKm exclusive (exceto o último que é inclusive).
/// Usar >= fromKm && < toKm elimina gaps e evitar que distâncias como 1.05 km
/// caiam no fallback de "+25km" gerando preços errados.
const List<_PriceTier> _motoTiers = [
  _PriceTier(0,  1,   8),
  _PriceTier(1,  2,  10),
  _PriceTier(2,  3,  12),
  _PriceTier(3,  4,  13),
  _PriceTier(4,  5,  14),
  _PriceTier(5,  6,  15),
  _PriceTier(6,  7,  16),
  _PriceTier(7,  8,  17),
  _PriceTier(8,  9,  20),
  _PriceTier(9,  10, 22),
  _PriceTier(10, 11, 22),
  _PriceTier(11, 12, 24),
  _PriceTier(12, 13, 26),
  _PriceTier(13, 14, 28),
  _PriceTier(14, 15, 32),
  _PriceTier(15, 16, 34),
  _PriceTier(16, 17, 36),
  _PriceTier(17, 18, 38),
  _PriceTier(18, 19, 40),
  _PriceTier(19, 20, 42),
  _PriceTier(20, 21, 44),
  _PriceTier(21, 22, 44),
  _PriceTier(22, 23, 46),
  _PriceTier(23, 24, 48),
  _PriceTier(24, 25, 50),
];

/// Tabela de preços — CARRO
/// ~50% acima da moto (custo operacional maior). Faixas contíguas.
const List<_PriceTier> _carTiers = [
  _PriceTier(0,  1,  12),
  _PriceTier(1,  2,  15),
  _PriceTier(2,  3,  18),
  _PriceTier(3,  4,  20),
  _PriceTier(4,  5,  22),
  _PriceTier(5,  6,  24),
  _PriceTier(6,  7,  26),
  _PriceTier(7,  8,  28),
  _PriceTier(8,  9,  32),
  _PriceTier(9,  10, 35),
  _PriceTier(10, 11, 35),
  _PriceTier(11, 12, 38),
  _PriceTier(12, 13, 40),
  _PriceTier(13, 14, 44),
  _PriceTier(14, 15, 48),
  _PriceTier(15, 16, 52),
  _PriceTier(16, 17, 55),
  _PriceTier(17, 18, 58),
  _PriceTier(18, 19, 60),
  _PriceTier(19, 20, 64),
  _PriceTier(20, 21, 66),
  _PriceTier(21, 22, 68),
  _PriceTier(22, 23, 70),
  _PriceTier(23, 24, 72),
  _PriceTier(24, 25, 75),
];

class PriceCalculator {
  /// Calcula o preço da entrega com base na distância, categoria e multiplicador dinâmico.
  ///
  /// Usa comparação [>= fromKm && < toKm] — faixas totalmente contíguas, sem gaps.
  /// A última faixa (24-25 km) usa [<= 25] para incluir o limite exato.
  /// Acima de 25 km: preço da última faixa + taxa por km extra.
  static double calculate(
    VehicleCategoryInfo category,
    double distanceKm, {
    double surgeMultiplier = 1.0,
  }) {
    final tiers = category.category == VehicleCategory.car
        ? _carTiers
        : _motoTiers;
    final lastTier = tiers.last;

    double base;

    if (distanceKm <= lastTier.toKm) {
      // Dentro das faixas tabeladas: busca a faixa correta
      // >= fromKm && < toKm para todas, exceto a última que usa <=
      _PriceTier? matched;
      for (int i = 0; i < tiers.length; i++) {
        final tier = tiers[i];
        final isLast = i == tiers.length - 1;
        final inRange = isLast
            ? distanceKm >= tier.fromKm && distanceKm <= tier.toKm
            : distanceKm >= tier.fromKm && distanceKm < tier.toKm;
        if (inRange) {
          matched = tier;
          break;
        }
      }
      // matched nunca será null aqui pois distanceKm <= lastTier.toKm
      base = matched?.price ?? tiers.first.price;
    } else {
      // Acima de 25 km: último tier + R$2/km extra (moto) ou R$3/km extra (carro)
      final extraKm = distanceKm - lastTier.toKm;
      final extraRate = category.category == VehicleCategory.car ? 3.0 : 2.0;
      base = lastTier.price + (extraKm * extraRate);
    }

    final total = base * surgeMultiplier;
    // Arredonda para o R$0,50 mais próximo para evitar valores com centavos estranhos
    return (total * 2).roundToDouble() / 2;
  }

  /// Retorna o preço mínimo (faixa 0-1 km) para exibição
  static double minFare(VehicleCategoryInfo category, {double surgeMultiplier = 1.0}) {
    final tiers = category.category == VehicleCategory.car
        ? _carTiers
        : _motoTiers;
    return tiers.first.price * surgeMultiplier;
  }

  static double commission(double value) => value * 0.25;

  static double netValue(double value) => value * 0.75;
}
