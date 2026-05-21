import 'package:latlong2/latlong.dart';

import '../../../data/models/route_result.dart';

class DeliverySession {
  final String deliveryId;
  final LatLng destination;
  final RouteResult routeResult;

  const DeliverySession({
    required this.deliveryId,
    required this.destination,
    required this.routeResult,
  });
}
