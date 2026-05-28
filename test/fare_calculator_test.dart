import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:arkgo/core/constants/vehicle_categories.dart';
import 'package:arkgo/data/models/route_result.dart';
import 'package:arkgo/data/services/fare_calculator.dart';

void main() {
  RouteResult route(double ratio) => RouteResult(
    distanceMeters: 5000,
    durationSeconds: 600,
    durationInTrafficSeconds: (600 * ratio).round(),
    source: RouteSource.google,
    polyline: const [LatLng(-23.55, -46.63), LatLng(-23.56, -46.64)],
    trafficRatio: ratio,
    computedAt: DateTime(2026, 5, 1),
  );

  group('FareCalculator', () {
    test('mantem sem adicional ate 1.10x', () {
      final breakdown = FareCalculator.calculateBreakdown(
        VehicleCategory.motoboy.info,
        5,
        routeResult: route(1.10),
      );
      expect(breakdown.trafficSurcharge, 0);
    });

    test('aplica 10% entre 1.10 e 1.30', () {
      final breakdown = FareCalculator.calculateBreakdown(
        VehicleCategory.motoboy.info,
        5,
        routeResult: route(1.20),
      );
      expect(breakdown.trafficSurcharge, 1.5);
    });

    test('aplica 20% entre 1.30 e 1.50', () {
      final breakdown = FareCalculator.calculateBreakdown(
        VehicleCategory.motoboy.info,
        5,
        routeResult: route(1.40),
      );
      expect(breakdown.trafficSurcharge, 3);
    });

    test('aplica cap de 30% acima de 1.50', () {
      final breakdown = FareCalculator.calculateBreakdown(
        VehicleCategory.motoboy.info,
        5,
        routeResult: route(1.80),
      );
      expect(breakdown.trafficSurcharge, 4.5);
    });

    test('soma pedagio e mantem compatibilidade sem RouteResult', () {
      final withTraffic = FareCalculator.calculateBreakdown(
        VehicleCategory.motoboy.info,
        5,
        routeResult: route(1.25),
        tollCostBrl: 4.8,
      );
      final legacy = FareCalculator.calculateFare(
        VehicleCategory.motoboy.info,
        5,
      );

      expect(withTraffic.totalFare, 21.3);
      expect(legacy, 15);
    });

    test('cobra metade da corrida no retorno quando ida e volta estiver ativa', () {
      final breakdown = FareCalculator.calculateBreakdown(
        VehicleCategory.motoboy.info,
        5,
        isRoundTrip: true,
      );

      expect(breakdown.baseFare, 15);
      expect(breakdown.returnTripFee, 7.5);
      expect(breakdown.totalFare, 22.5);
    });
  });
}
