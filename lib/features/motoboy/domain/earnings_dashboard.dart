class EarningsPoint {
  final String label;
  final double value;

  const EarningsPoint({required this.label, required this.value});
}

class EarningsDashboard {
  final double today;
  final double week;
  final double month;
  final List<EarningsPoint> dailyPoints;
  final List<EarningsPoint> weeklyPoints;
  final List<EarningsPoint> monthlyPoints;

  const EarningsDashboard({
    required this.today,
    required this.week,
    required this.month,
    required this.dailyPoints,
    required this.weeklyPoints,
    required this.monthlyPoints,
  });
}
