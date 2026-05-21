class AppConstants {
  static const double commissionRate = 0.25;
  static const String appName = 'ArkGo';
  static const int locationUpdateIntervalSeconds = 5;
  static const double minimumRechargeAmount = 10.0;

  /// Google Maps tile URL (Limpo, estilo Uber — sem empresas, hospitais, locais)
  static const String mapTileUrl =
      'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&apistyle=s.t:2|p.v:off,s.t:3';
}
