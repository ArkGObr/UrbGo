import 'package:flutter/material.dart';

enum VehicleCategory {
  motoboy,
  car,
  // Desativadas por enquanto — serão habilitadas após validação
  // bike,
  // mototaxi,
  // van,
  // truck,
}

class VehicleCategoryInfo {
  final VehicleCategory category;
  final String id;
  final String name;
  final IconData icon;
  final String description;
  final String capacity;
  final double baseRate;
  final double perKmRate;
  final double minFare;
  final int etaMultiplier;

  const VehicleCategoryInfo({
    required this.category,
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.capacity,
    required this.baseRate,
    required this.perKmRate,
    required this.minFare,
    required this.etaMultiplier,
  });
}

/// Todas as categorias disponíveis no app (apenas as ativas).
const List<VehicleCategoryInfo> vehicleCategories = [
  VehicleCategoryInfo(
    category: VehicleCategory.motoboy,
    id: 'motoboy',
    name: 'Moto',
    icon: Icons.two_wheeler_rounded,
    description: 'Entregas rápidas, documentos, pequenas cargas',
    capacity: 'Até 20 kg',
    baseRate: 5.00,
    perKmRate: 1.50,
    minFare: 8.00,
    etaMultiplier: 100,
  ),
  VehicleCategoryInfo(
    category: VehicleCategory.car,
    id: 'car',
    name: 'Carro',
    icon: Icons.directions_car_rounded,
    description: 'Encomendas médias, múltiplos volumes',
    capacity: 'Até 100 kg',
    baseRate: 10.00,
    perKmRate: 2.50,
    minFare: 18.00,
    etaMultiplier: 115,
  ),
];

extension VehicleCategoryExtension on VehicleCategory {
  VehicleCategoryInfo get info =>
      vehicleCategories.firstWhere((v) => v.category == this);

  static VehicleCategory fromId(String id) {
    final match = vehicleCategories.where((v) => v.id == id);
    if (match.isEmpty) return VehicleCategory.motoboy; // fallback
    return match.first.category;
  }
}

class PriceCalculator {
  static double calculate(VehicleCategoryInfo category, double distanceKm) {
    final calculated = category.baseRate + (distanceKm * category.perKmRate);
    return calculated < category.minFare ? category.minFare : calculated;
  }

  static double commission(double value) => value * 0.25;

  static double netValue(double value) => value * 0.75;
}
