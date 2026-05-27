class InvestmentPriceHistory {
  final String id;
  final String userId;
  final String accountId;
  final String holdingId;
  final String symbol;
  final String assetClass;
  final String currency;
  final double price;
  final double quantitySnapshot;
  final String source;
  final DateTime marketDate;
  final DateTime fetchedAt;

  const InvestmentPriceHistory({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.holdingId,
    required this.symbol,
    required this.assetClass,
    required this.currency,
    required this.price,
    required this.quantitySnapshot,
    required this.source,
    required this.marketDate,
    required this.fetchedAt,
  });

  factory InvestmentPriceHistory.fromJson(Map<String, dynamic> json) {
    return InvestmentPriceHistory(
      id: json['id'],
      userId: json['user_id'],
      accountId: json['account_id'],
      holdingId: json['holding_id'],
      symbol: json['symbol'],
      assetClass: json['asset_class'],
      currency: json['currency'] ?? 'COP',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantitySnapshot: (json['quantity_snapshot'] as num?)?.toDouble() ?? 0.0,
      source: json['source'] ?? 'manual',
      marketDate: DateTime.parse(json['market_date']),
      fetchedAt: DateTime.parse(json['fetched_at']),
    );
  }

  double get positionValue => price * quantitySnapshot;
}
