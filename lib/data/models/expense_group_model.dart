class ExpenseGroup {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime? endDate;
  final double budgetAmount;
  final String? icon;

  ExpenseGroup({
    required this.id,
    required this.name,
    required this.startDate,
    this.endDate,
    this.budgetAmount = 0.0,
    this.icon,
  });

  factory ExpenseGroup.fromJson(Map<String, dynamic> json) {
    return ExpenseGroup(
      id: json['id'],
      name: json['name'],
      startDate: DateTime.parse(json['start_date']),
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date']) : null,
      budgetAmount: (json['budget_amount'] as num?)?.toDouble() ?? 0.0,
      icon: json['icon'],
    );
  }
}
