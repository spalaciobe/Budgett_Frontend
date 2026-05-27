class InvestmentPurchaseEvent {
  final String holdingId;
  final DateTime date;
  final double quantity;
  final double amount;
  final String source;

  const InvestmentPurchaseEvent({
    required this.holdingId,
    required this.date,
    required this.quantity,
    required this.amount,
    required this.source,
  });

  factory InvestmentPurchaseEvent.fromTransactionJson(
    Map<String, dynamic> json,
  ) {
    return InvestmentPurchaseEvent(
      holdingId: json['holding_id'],
      date: DateTime.parse(json['date']),
      quantity: (json['holding_qty_delta'] as num?)?.toDouble() ?? 0.0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      source: 'transaction',
    );
  }

  factory InvestmentPurchaseEvent.fromHoldingCreatedAt({
    required String holdingId,
    required DateTime createdAt,
    required double quantity,
    required double amount,
  }) {
    return InvestmentPurchaseEvent(
      holdingId: holdingId,
      date: createdAt,
      quantity: quantity,
      amount: amount,
      source: 'created_at',
    );
  }
}
