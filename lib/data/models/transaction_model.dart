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

  // Installment ("cuotas") fields
  final String? parentTransactionId;
  final bool isInstallmentParent;
  final int? numCuotas;
  final int? installmentNumber; // 1..N on children; null on parent
  final bool? hasInterest;
  final double? interestRate; // monthly decimal, e.g. 0.025
  final double? originalPurchaseAmount; // populated only on parent

  // Credit card payment flow
  final bool isCreditCardPayment;
  final List<String> closedInstallmentIds;

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
    this.parentTransactionId,
    this.isInstallmentParent = false,
    this.numCuotas,
    this.installmentNumber,
    this.hasInterest,
    this.interestRate,
    this.originalPurchaseAmount,
    this.isCreditCardPayment = false,
    this.closedInstallmentIds = const [],
  });

  bool get isCrossCurrencyPayment =>
      targetCurrency != null && targetCurrency != currency;

  bool get isInstallmentChild => parentTransactionId != null;
  bool get isInstallment => isInstallmentParent || isInstallmentChild;

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
      parentTransactionId: json['parent_transaction_id'] as String?,
      isInstallmentParent: (json['is_installment_parent'] as bool?) ?? false,
      numCuotas: json['num_cuotas'] as int?,
      installmentNumber: json['installment_number'] as int?,
      hasInterest: json['has_interest'] as bool?,
      interestRate: (json['interest_rate'] as num?)?.toDouble(),
      originalPurchaseAmount:
          (json['original_purchase_amount'] as num?)?.toDouble(),
      isCreditCardPayment:
          (json['is_credit_card_payment'] as bool?) ?? false,
      closedInstallmentIds: (json['closed_installment_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}
