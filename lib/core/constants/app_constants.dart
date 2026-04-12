import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static const double commissionRate = 0.25;
  static const String appName = 'UrbGo';
  static const int locationUpdateIntervalSeconds = 5;
  static const double minimumRechargeAmount = 10.0;
  static const String orsBaseUrl = 'https://api.openrouteservice.org';
  static String get orsApiKey => dotenv.env['ORS_API_KEY'] ?? '';

  /// Google Maps tile URL (Limpo, estilo Uber — sem empresas, hospitais, locais)
  static const String mapTileUrl =
      'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&apistyle=s.t:2|p.v:off,s.t:3';
}
