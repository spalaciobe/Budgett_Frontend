class Transaction {
  final String id;
  final String accountId;
  final double amount;
  final String description;
  final DateTime date;
  final String type; // income, expense, transfer
  final String? categoryId;
  final String? targetAccountId;
  final String status; // pending, cleared
  final String? movementType; // fixed, variable, savings, income, transfer
  final String? expenseGroupId;
  final String? notes;
  final String? place;

  Transaction({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.description,
    required this.date,
    required this.type,
    this.categoryId,
    this.targetAccountId,
    this.status = 'cleared',
    this.movementType,
    this.expenseGroupId,
    this.notes,
    this.place,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      accountId: json['account_id'],
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] ?? '',
      date: DateTime.parse(json['date']),
      type: json['type'],
      categoryId: json['category_id'],
      targetAccountId: json['target_account_id'],
      status: json['status'] ?? 'cleared',
      movementType: json['movement_type'],
      expenseGroupId: json['expense_group_id'],
      notes: json['notes'],
      place: json['place'],
    );
  }
}
