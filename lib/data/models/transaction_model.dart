class Transaction {
  final String id;
  final String accountId;
  final double amount;
  final String description;
  final DateTime date;
  final String type; // income, expense, transfer
  final String? categoryId;
  final String? subCategoryId;
  final String? targetAccountId;
  final String status; // pending, cleared
  final String? movementType; // fixed, variable, savings, income, transfer
  final String? expenseGroupId;
  final String? notes;
  final String? place;

  // Currency fields
  final String currency; // 'COP' or 'USD'
  final String? targetCurrency; // set on cross-currency transfers
  final double? fxRate; // COP per 1 USD, required when targetCurrency differs

  // Credit Card Specific
  final String? billingPeriod;
  final DateTime? calculatedCutoffDate;
  final DateTime? calculatedPaymentDate;

  Transaction({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.description,
    required this.date,
    required this.type,
    this.categoryId,
    this.subCategoryId,
    this.targetAccountId,
    this.status = 'cleared',
    this.movementType,
    this.expenseGroupId,
    this.notes,
    this.place,
    this.currency = 'COP',
    this.targetCurrency,
    this.fxRate,
    this.billingPeriod,
    this.calculatedCutoffDate,
    this.calculatedPaymentDate,
  });

  bool get isCrossCurrencyPayment =>
      targetCurrency != null && targetCurrency != currency;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      accountId: json['account_id'],
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] ?? '',
      date: DateTime.parse(json['date']),
      type: json['type'],
      categoryId: json['category_id'],
      subCategoryId: json['sub_category_id'],
      targetAccountId: json['target_account_id'],
      status: json['status'] ?? 'cleared',
      movementType: json['movement_type'],
      expenseGroupId: json['expense_group_id'],
      notes: json['notes'],
      place: json['place'],
      currency: json['currency'] as String? ?? 'COP',
      targetCurrency: json['target_currency'] as String?,
      fxRate: (json['fx_rate'] as num?)?.toDouble(),
      billingPeriod: json['periodo_facturacion'],
      calculatedCutoffDate: json['fecha_corte_calculada'] != null
          ? DateTime.parse(json['fecha_corte_calculada'])
          : null,
      calculatedPaymentDate: json['fecha_pago_calculada'] != null
          ? DateTime.parse(json['fecha_pago_calculada'])
          : null,
    );
  }
}
