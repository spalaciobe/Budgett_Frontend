class Budget {
  final String id;
  final String categoryId;
  final double amount; // Budgeted amount
  final int month;
  final int year;

  Budget({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.month,
    required this.year,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      categoryId: json['category_id'],
      amount: (json['amount'] as num).toDouble(),
      month: json['month'],
      year: json['year'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'amount': amount,
      'month': month,
      'year': year,
    };
  }
}
