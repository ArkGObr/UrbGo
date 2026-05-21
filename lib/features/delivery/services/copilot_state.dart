import 'package:latlong2/latlong.dart';

import '../../../data/models/route_result.dart';

enum CopilotUiStatus { idle, monitoring, alert, rerouteAccepted }

class CopilotState {
  final bool isMonitoring;
  final double currentSpeedKmh;
  final double expectedSpeedKmh;
  final double ratio;
  final DateTime? lastAlert;
  final String? alertMessage;
  final RouteResult? suggestedRoute;
  final int timeSavedMinutes;
  final CopilotUiStatus status;
  final LatLng? currentPosition;

  const CopilotState({
    this.isMonitoring = false,
    this.currentSpeedKmh = 0,
    this.expectedSpeedKmh = 0,
    this.ratio = 1,
    this.lastAlert,
    this.alertMessage,
    this.suggestedRoute,
    this.timeSavedMinutes = 0,
    this.status = CopilotUiStatus.idle,
    this.currentPosition,
  });

  CopilotState copyWith({
    bool? isMonitoring,
    double? currentSpeedKmh,
    double? expectedSpeedKmh,
    double? ratio,
    DateTime? lastAlert,
    String? alertMessage,
    RouteResult? suggestedRoute,
    int? timeSavedMinutes,
    CopilotUiStatus? status,
    LatLng? currentPosition,
    bool clearAlert = false,
  }) {
    return CopilotState(
      isMonitoring: isMonitoring ?? this.isMonitoring,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      expectedSpeedKmh: expectedSpeedKmh ?? this.expectedSpeedKmh,
      ratio: ratio ?? this.ratio,
      lastAlert: lastAlert ?? this.lastAlert,
      alertMessage: clearAlert ? null : alertMessage ?? this.alertMessage,
      suggestedRoute: clearAlert ? null : suggestedRoute ?? this.suggestedRoute,
      timeSavedMinutes: clearAlert
          ? 0
          : timeSavedMinutes ?? this.timeSavedMinutes,
      status: status ?? this.status,
      currentPosition: currentPosition ?? this.currentPosition,
    );
  }
}
