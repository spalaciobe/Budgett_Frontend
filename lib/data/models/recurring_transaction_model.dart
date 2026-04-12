class RecurringTransaction {
  final String id;
  final String description;
  final double amount;
  final String? categoryId;
  final String? accountId;
  final String type; // 'income', 'expense', 'transfer'
  final String frequency; // 'daily', 'weekly', 'biweekly', 'monthly', 'yearly'
  final DateTime nextRunDate;
  final DateTime? lastRunDate;
  final bool isActive;
  final String currency; // 'COP' or 'USD'

  RecurringTransaction({
    required this.id,
    required this.description,
    required this.amount,
    this.categoryId,
    this.accountId,
    required this.type,
    required this.frequency,
    required this.nextRunDate,
    this.lastRunDate,
    required this.isActive,
    this.currency = 'COP',
  });

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    return RecurringTransaction(
      id: json['id'],
      description: json['description'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      categoryId: json['category_id'],
      accountId: json['account_id'],
      type: json['type'],
      frequency: json['frequency'],
      nextRunDate: DateTime.parse(json['next_run_date']),
      lastRunDate: json['last_run_date'] != null ? DateTime.parse(json['last_run_date']) : null,
      isActive: json['is_active'] ?? true,
      currency: json['currency'] as String? ?? 'COP',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'amount': amount,
      'category_id': categoryId,
      'account_id': accountId,
      'type': type,
      'frequency': frequency,
      'next_run_date': nextRunDate.toIso8601String().split('T')[0],
      'is_active': isActive,
      'currency': currency,
    };
  }
}
