import '../../core/constants/vehicle_categories.dart';
import '../models/fare_breakdown.dart';
import '../models/route_result.dart';

class FareCalculator {
  const FareCalculator._();

  static double calculateFare(
    VehicleCategoryInfo category,
    double distanceKm, {
    double surgeMultiplier = 1,
    RouteResult? routeResult,
    double tollCostBrl = 0,
  }) {
    return calculateBreakdown(
      category,
      distanceKm,
      surgeMultiplier: surgeMultiplier,
      routeResult: routeResult,
      tollCostBrl: tollCostBrl,
    ).totalFare;
  }

  static FareBreakdown calculateBreakdown(
    VehicleCategoryInfo category,
    double distanceKm, {
    double surgeMultiplier = 1,
    RouteResult? routeResult,
    double tollCostBrl = 0,
  }) {
    final baseFare = _round(
      PriceCalculator.calculate(
        category,
        distanceKm,
        surgeMultiplier: surgeMultiplier,
      ),
    );
    final ratio = routeResult?.trafficRatio ?? 1;
    final surchargeRate = _surchargeRate(ratio);
    final trafficSurcharge = _round(baseFare * surchargeRate);
    final tollCost = _round(routeResult?.tollCostBrl ?? tollCostBrl);
    final totalFare = _round(baseFare + trafficSurcharge + tollCost);

    return FareBreakdown(
      baseFare: baseFare,
      trafficSurcharge: trafficSurcharge,
      tollCost: tollCost,
      totalFare: totalFare,
      trafficRatioDisplay:
          '${ratio.toStringAsFixed(1)}x mais lento que o normal',
      surchargeLabel: trafficSurcharge > 0
          ? 'Adicional de trafego: R\$ ${trafficSurcharge.toStringAsFixed(2)}'
          : 'Sem adicional de trafego',
    );
  }

  static double _surchargeRate(double ratio) {
    if (ratio <= 1.10) return 0;
    if (ratio <= 1.30) return 0.10;
    if (ratio <= 1.50) return 0.20;
    return 0.30;
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));
}
