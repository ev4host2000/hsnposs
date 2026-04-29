class Report {
  final String id;
  final DateTime date;
  final double totalSales;
  final double totalExpenses;
  final double profit;

  Report({
    required this.id,
    required this.date,
    required this.totalSales,
    required this.totalExpenses,
    required this.profit,
  });
}