class ExpenseGroup {
  final String id;
  final String name;
  final int month;
  final int year;
  final double budgetAmount;
  final String? icon;

  ExpenseGroup({
    required this.id,
    required this.name,
    required this.month,
    required this.year,
    this.budgetAmount = 0.0,
    this.icon,
  });

  factory ExpenseGroup.fromJson(Map<String, dynamic> json) {
    return ExpenseGroup(
      id: json['id'],
      name: json['name'],
      month: json['month'],
      year: json['year'],
      budgetAmount: (json['budget_amount'] as num?)?.toDouble() ?? 0.0,
      icon: json['icon'],
    );
  }
}
