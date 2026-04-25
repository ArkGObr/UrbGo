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
  final String detailedCapacity;
  final int etaMultiplier;

  // Propriedades por categoria
  final bool isMotoTaxi;
  final bool helperSupported;
  final bool isEco;
  final double? maxDistanceKm;
  final double maxWeightKg;

  const VehicleCategoryInfo({
    required this.category,
    required this.id,
    required this.name,
    required this.icon,
    this.assetPath,
    required this.description,
    required this.capacity,
    required this.detailedCapacity,
    required this.etaMultiplier,
    this.isMotoTaxi = false,
    this.helperSupported = false,
    this.isEco = false,
    this.maxDistanceKm,
    required this.maxWeightKg,
  });
}

/// Todas as categorias disponíveis no app
const List<VehicleCategoryInfo> vehicleCategories = [
  VehicleCategoryInfo(
    category: VehicleCategory.motoboy,
    id: 'motoboy',
    name: 'Moto Entregas',
    icon: Icons.two_wheeler_rounded,
    description: 'Pacotes, documentos, rápido',
    capacity: 'Até 20 kg',
    detailedCapacity: 'Até 20 kg / itens pequenos',
    etaMultiplier: 100,
    maxWeightKg: 20,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.car,
    id: 'car',
    name: 'Carro Entregas',
    icon: Icons.directions_car_rounded,
    description: 'Caixas, itens maiores',
    capacity: 'Até 50 kg',
    detailedCapacity: 'Até 50 kg / porta-malas',
    etaMultiplier: 115,
    maxWeightKg: 50,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.bike,
    id: 'bike',
    name: 'Bike Entregas',
    icon: Icons.pedal_bike_rounded,
    description: 'Ecológico, curtas distâncias',
    capacity: 'Até 5 kg / 3 km',
    detailedCapacity: 'Até 5 kg / máx. 3 km',
    etaMultiplier: 150,
    isEco: true,
    maxDistanceKm: 3.0,
    maxWeightKg: 5,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.mototaxi,
    id: 'mototaxi',
    name: 'Moto Táxi',
    icon: Icons.motorcycle_rounded,
    description: 'Corrida de passageiro',
    capacity: '1 passageiro',
    detailedCapacity: '1 passageiro / sem bagagem',
    etaMultiplier: 100,
    isMotoTaxi: true,
    maxWeightKg: 0,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.van,
    id: 'van',
    name: 'Utilitário',
    icon: Icons.airport_shuttle_rounded,
    assetPath: 'assets/utilitario.png',
    description: 'Móveis, eletrodomésticos',
    capacity: 'Até 650 kg',
    detailedCapacity: 'Até 650 kg / 2.500 L',
    etaMultiplier: 130,
    helperSupported: true,
    maxWeightKg: 650,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.truck,
    id: 'truck',
    name: 'Carreto',
    icon: Icons.local_shipping_rounded,
    assetPath: 'assets/caminhao.png',
    description: 'Mudanças, carga pesada',
    capacity: 'Até 2.500 kg',
    detailedCapacity: 'Até 2.500 kg / mudanças',
    etaMultiplier: 160,
    helperSupported: true,
    maxWeightKg: 2500,
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

/// Tabela de preços — CARRO (~50% acima da moto)
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
  /// Calcula o preço base (distância) + surge multiplier.
  /// Bike, Van, Truck usam tabela moto como base.
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
      base = matched?.price ?? tiers.first.price;
    } else {
      final extraKm = distanceKm - lastTier.toKm;
      final extraRate = category.category == VehicleCategory.car ? 3.0 : 2.0;
      base = lastTier.price + (extraKm * extraRate);
    }

    // Van e Truck têm multiplicador de preço adicional
    double categoryMultiplier = 1.0;
    if (category.category == VehicleCategory.van) categoryMultiplier = 1.4;
    if (category.category == VehicleCategory.truck) categoryMultiplier = 1.8;

    final total = base * surgeMultiplier * categoryMultiplier;
    return (total * 2).roundToDouble() / 2;
  }

  /// Preço adicional por helper (por contratação, não por km)
  static double helperFee(int helperCount) => helperCount * 15.0;

  static double minFare(VehicleCategoryInfo category, {double surgeMultiplier = 1.0}) {
    final tiers = category.category == VehicleCategory.car
        ? _carTiers
        : _motoTiers;
    double base = tiers.first.price;
    double categoryMultiplier = 1.0;
    if (category.category == VehicleCategory.van) categoryMultiplier = 1.4;
    if (category.category == VehicleCategory.truck) categoryMultiplier = 1.8;
    return base * surgeMultiplier * categoryMultiplier;
  }

  static double commission(double value) => value * 0.25;
  static double netValue(double value) => value * 0.75;
}
