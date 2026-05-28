class FareBreakdown {
  final double baseFare;
  final double trafficSurcharge;
  final double returnTripFee;
  final double tollCost;
  final double totalFare;
  final String trafficRatioDisplay;
  final String surchargeLabel;

  const FareBreakdown({
    required this.baseFare,
    required this.trafficSurcharge,
    required this.returnTripFee,
    required this.tollCost,
    required this.totalFare,
    required this.trafficRatioDisplay,
    required this.surchargeLabel,
  });

  Map<String, dynamic> toJson() => {
    'baseFare': baseFare,
    'trafficSurcharge': trafficSurcharge,
    'returnTripFee': returnTripFee,
    'tollCost': tollCost,
    'totalFare': totalFare,
    'trafficRatioDisplay': trafficRatioDisplay,
    'surchargeLabel': surchargeLabel,
  };
}
