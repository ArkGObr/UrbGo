import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnalyticsSummary {
  final int totalRides;
  final double totalMinutesSaved;
  final double avgTrafficRatio;
  final double totalTollsCollectedBrl;
  final double aiAccuracyPercent;
  final double rerouteAcceptanceRate;

  const AnalyticsSummary({
    required this.totalRides,
    required this.totalMinutesSaved,
    required this.avgTrafficRatio,
    required this.totalTollsCollectedBrl,
    required this.aiAccuracyPercent,
    required this.rerouteAcceptanceRate,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) =>
      AnalyticsSummary(
        totalRides: json['totalRides'] as int? ?? 0,
        totalMinutesSaved: (json['totalMinutesSaved'] as num?)?.toDouble() ?? 0,
        avgTrafficRatio: (json['avgTrafficRatio'] as num?)?.toDouble() ?? 0,
        totalTollsCollectedBrl:
            (json['totalTollsCollectedBRL'] as num?)?.toDouble() ?? 0,
        aiAccuracyPercent: (json['aiAccuracyPercent'] as num?)?.toDouble() ?? 0,
        rerouteAcceptanceRate:
            (json['rerouteAcceptanceRate'] as num?)?.toDouble() ?? 0,
      );
}

class AnalyticsPayload {
  final AnalyticsSummary summary;
  final List<Map<String, dynamic>> timeSeries;
  final List<Map<String, dynamic>> topCorridors;
  final Map<String, dynamic> costAnalysis;
  final List<Map<String, dynamic>> recentEvents;
  final int activeAiRides;

  const AnalyticsPayload({
    required this.summary,
    required this.timeSeries,
    required this.topCorridors,
    required this.costAnalysis,
    required this.recentEvents,
    required this.activeAiRides,
  });

  factory AnalyticsPayload.fromJson(Map<String, dynamic> json) =>
      AnalyticsPayload(
        summary: AnalyticsSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
        timeSeries: (json['timeSeries'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>(),
        topCorridors: (json['topCorridors'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>(),
        costAnalysis: json['costAnalysis'] as Map<String, dynamic>? ?? const {},
        recentEvents: (json['recentEvents'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>(),
        activeAiRides:
            (json['liveNow'] as Map<String, dynamic>? ??
                    const {})['activeAiRides']
                as int? ??
            0,
      );

  String toCache() => jsonEncode({
    'summary': {
      'totalRides': summary.totalRides,
      'totalMinutesSaved': summary.totalMinutesSaved,
      'avgTrafficRatio': summary.avgTrafficRatio,
      'totalTollsCollectedBRL': summary.totalTollsCollectedBrl,
      'aiAccuracyPercent': summary.aiAccuracyPercent,
      'rerouteAcceptanceRate': summary.rerouteAcceptanceRate,
    },
    'timeSeries': timeSeries,
    'topCorridors': topCorridors,
    'costAnalysis': costAnalysis,
    'recentEvents': recentEvents,
    'liveNow': {'activeAiRides': activeAiRides},
  });
}

class AnalyticsNotifier extends AsyncNotifier<AnalyticsPayload> {
  final Dio _dio = Dio();
  String _period = '7d';
  String? _etag;
  AnalyticsPayload? _cached;

  @override
  Future<AnalyticsPayload> build() => _load();

  Future<void> setPeriod(String period) async {
    _period = period;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<AnalyticsPayload> _load() async {
    final baseUrl = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (baseUrl == null || anonKey == null) {
      if (_cached != null) return _cached!;
      throw Exception('SUPABASE_URL/SUPABASE_ANON_KEY ausentes');
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/functions/v1/analytics-metrics?period=$_period',
      options: Options(
        headers: {
          'Authorization': 'Bearer $anonKey',
          'apikey': anonKey,
          if (_etag != null) 'If-None-Match': _etag,
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode == 304 && _cached != null) {
      return _cached!;
    }

    final data = AnalyticsPayload.fromJson(response.data ?? const {});
    _etag = response.headers.value('etag');
    _cached = data;
    return data;
  }
}

final analyticsProvider =
    AsyncNotifierProvider<AnalyticsNotifier, AnalyticsPayload>(
      AnalyticsNotifier.new,
    );
