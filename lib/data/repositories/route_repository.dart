import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/route_service.dart' as legacy;
import '../models/route_result.dart';

final routeRepositoryProvider = Provider<RouteRepository>(
  (ref) => RouteRepository(),
);

class RouteRepository {
  RouteRepository({Dio? dio, legacy.RouteService? routeService})
    : _dio = dio ?? Dio(),
      _routeService = routeService ?? legacy.RouteService();

  final Dio _dio;
  final legacy.RouteService _routeService;

  /// Resolve uma rota híbrida entre OSRM e Google Routes.
  Future<RouteResult> resolveRoute(
    LatLng origin,
    LatLng destination, {
    required bool isUrgent,
  }) async {
    try {
      if (!shouldQueryLiveTraffic(origin, destination, isUrgent: isUrgent)) {
        return _queryOSRM(origin, destination);
      }

      final results = await Future.wait<RouteResult?>([
        _queryOSRM(origin, destination),
        _queryGoogleRoutes(origin, destination),
      ]);

      return results[1] ?? results[0]!;
    } catch (error, stackTrace) {
      throw AppException(
        'Nao foi possivel calcular a rota.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Decide se vale pagar por tráfego ao vivo para este trecho.
  bool shouldQueryLiveTraffic(
    LatLng origin,
    LatLng destination, {
    required bool isUrgent,
    DateTime? now,
  }) {
    if (isUrgent) return true;

    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      origin,
      destination,
    );
    if (distanceKm > 8) return true;

    final current = now ?? DateTime.now();
    final isWeekday =
        current.weekday >= DateTime.monday &&
        current.weekday <= DateTime.friday;
    final isPeakHour =
        (current.hour >= 7 && current.hour < 9) ||
        (current.hour >= 17 && current.hour < 19);

    return isWeekday && isPeakHour;
  }

  /// Fallback gratuito usando o serviço OSRM já existente no app.
  Future<RouteResult> _queryOSRM(LatLng origin, LatLng destination) async {
    final route = await _routeService.getRouteWithInfo(origin, destination);
    return RouteResult(
      distanceMeters: route.distanceKm * 1000,
      durationSeconds: route.durationSeconds,
      durationInTrafficSeconds: route.durationSeconds,
      source: RouteSource.osrm,
      polyline: route.points,
      trafficRatio: 1,
      tollCostBrl:
          route.advisories.any(
            (advisory) => advisory.type == legacy.RouteAdvisoryType.toll,
          )
          ? 4.8
          : 0,
      computedAt: DateTime.now(),
    );
  }

  /// Consulta o endpoint de decisão em Supabase/Google Routes.
  Future<RouteResult?> _queryGoogleRoutes(
    LatLng origin,
    LatLng destination,
  ) async {
    final baseUrl = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (baseUrl == null || anonKey == null) {
      debugPrint('[RouteRepository] TODO: configurar SUPABASE_URL e ANON key.');
      return null;
    }

    final functionUrl = '$baseUrl/functions/v1/routing-decision';
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        functionUrl,
        data: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'isUrgent': true,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $anonKey', 'apikey': anonKey},
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final data = response.data;
      if (data == null) return null;
      return RouteResult.fromJson(data);
    } catch (error) {
      debugPrint('[RouteRepository] Google Routes indisponivel: $error');
      return null;
    }
  }
}
