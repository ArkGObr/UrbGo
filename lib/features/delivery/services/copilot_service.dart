import 'dart:async';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/route_result.dart';
import '../domain/delivery_session.dart';
import 'alert_service.dart';
import 'copilot_settings.dart';
import 'copilot_state.dart';

final copilotServiceProvider =
    StateNotifierProvider<CopilotService, CopilotState>((ref) {
      return CopilotService(ref);
    });

class CopilotService extends StateNotifier<CopilotState> {
  CopilotService(this._ref) : super(const CopilotState());

  final Ref _ref;
  final Dio _dio = Dio();
  StreamSubscription<Position>? _positionSubscription;
  DeliverySession? _session;
  DateTime? _lastAiRefresh;
  double _expectedSpeedKmh = 35;

  Future<void> startMonitoring(DeliverySession session) async {
    _session = session;
    _expectedSpeedKmh = _deriveExpectedSpeed(session.routeResult);
    _lastAiRefresh = DateTime.now();
    state = state.copyWith(
      isMonitoring: true,
      expectedSpeedKmh: _expectedSpeedKmh,
      status: CopilotUiStatus.monitoring,
      clearAlert: true,
    );

    await _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
          ),
        ).listen((position) {
          unawaited(Isolate.run(() => position).then((pos) => _evaluate(pos)));
        });
  }

  Future<void> _evaluate(Position pos) async {
    final session = _session;
    if (session == null) return;

    final currentSpeedKmh = pos.speed * 3.6;
    if (currentSpeedKmh < 2) return;

    final now = DateTime.now();
    if (_lastAiRefresh == null ||
        now.difference(_lastAiRefresh!).inMinutes >= 2) {
      await _refreshAiExpectedSpeed(
        LatLng(pos.latitude, pos.longitude),
        session.destination,
      );
      _lastAiRefresh = now;
    }

    final ratio =
        currentSpeedKmh / (_expectedSpeedKmh == 0 ? 1 : _expectedSpeedKmh);
    state = state.copyWith(
      currentSpeedKmh: currentSpeedKmh,
      expectedSpeedKmh: _expectedSpeedKmh,
      ratio: ratio,
      currentPosition: LatLng(pos.latitude, pos.longitude),
      status: state.status == CopilotUiStatus.alert
          ? CopilotUiStatus.alert
          : CopilotUiStatus.monitoring,
    );

    if (ratio <= 0.85) {
      await _triggerRerouteAlert(LatLng(pos.latitude, pos.longitude), session);
    }
  }

  Future<void> _refreshAiExpectedSpeed(
    LatLng origin,
    LatLng destination,
  ) async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (supabaseUrl == null || anonKey == null) return;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$supabaseUrl/functions/v1/gemini-routing',
        data: {
          'origin': '${origin.latitude}:${origin.longitude}',
          'destination': '${destination.latitude}:${destination.longitude}',
          'avoidCurrentCorridor': true,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $anonKey', 'apikey': anonKey},
        ),
      );
      final optimized =
          response.data?['optimizedRoute'] as Map<String, dynamic>?;
      if (optimized == null) return;
      final durationSeconds =
          (optimized['durationSeconds'] as num?)?.toDouble() ?? 0;
      final distanceMeters =
          (optimized['distanceMeters'] as num?)?.toDouble() ?? 0;
      if (durationSeconds > 0 && distanceMeters > 0) {
        _expectedSpeedKmh = (distanceMeters / 1000) / (durationSeconds / 3600);
      }
    } catch (_) {}
  }

  Future<void> _triggerRerouteAlert(
    LatLng origin,
    DeliverySession session,
  ) async {
    if (state.lastAlert != null &&
        DateTime.now().difference(state.lastAlert!).inMinutes < 5) {
      return;
    }

    final alternativeRoute = await _fetchAlternativeRoute(
      origin,
      session.destination,
    );
    if (alternativeRoute == null) return;

    final currentEta = session.routeResult.durationInTrafficSeconds;
    final timeSavedMinutes =
        ((currentEta - alternativeRoute.durationInTrafficSeconds) / 60).round();
    final minSaving = _ref
        .read(copilotSettingsProvider)
        .minimumTimeSavingMinutes;
    if (timeSavedMinutes <= minSaving) return;

    final message = 'Economize $timeSavedMinutes min com um desvio sugerido';
    state = state.copyWith(
      lastAlert: DateTime.now(),
      alertMessage: message,
      suggestedRoute: alternativeRoute,
      timeSavedMinutes: timeSavedMinutes,
      status: CopilotUiStatus.alert,
    );
    await _ref
        .read(alertServiceProvider)
        .sendRerouteAlert(message, alternativeRoute, timeSavedMinutes);
  }

  Future<RouteResult?> _fetchAlternativeRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (supabaseUrl == null || anonKey == null) return null;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$supabaseUrl/functions/v1/routing-decision',
        data: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'isUrgent': true,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $anonKey', 'apikey': anonKey},
        ),
      );
      final data = response.data;
      if (data == null) return null;
      return RouteResult.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  void acceptReroute(RouteResult newRoute) {
    _session = _session == null
        ? null
        : DeliverySession(
            deliveryId: _session!.deliveryId,
            destination: _session!.destination,
            routeResult: newRoute,
          );
    _expectedSpeedKmh = _deriveExpectedSpeed(newRoute);
    state = state.copyWith(
      expectedSpeedKmh: _expectedSpeedKmh,
      status: CopilotUiStatus.rerouteAccepted,
      clearAlert: true,
    );
  }

  void dismissAlert() {
    state = state.copyWith(
      status: CopilotUiStatus.monitoring,
      clearAlert: true,
    );
  }

  Future<void> stopMonitoring() async {
    await _positionSubscription?.cancel();
    _session = null;
    state = const CopilotState();
  }

  double _deriveExpectedSpeed(RouteResult route) {
    if (route.durationInTrafficSeconds <= 0) return 35;
    return route.distanceKm / (route.durationInTrafficSeconds / 3600);
  }
}
