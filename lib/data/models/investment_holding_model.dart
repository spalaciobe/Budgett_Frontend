class InvestmentHolding {
  final String id;
  final String userId;
  final String accountId;
  final String symbol;
  final String? name;
  final String assetClass;
  final String currency;
  final double quantity;
  final double avgCost;
  final double currentPrice;
  final DateTime? priceUpdatedAt;
  final String? notes;
  /// Optional external-source lookup key. For FICs this is the exact
  /// `nombre_patrimonio` on datos.gov.co (dataset qhpu-8ixx) used by the
  /// `update-prices` Edge Function. Null for crypto/stocks.
  final String? sourceSymbol;

  /// When true, this holding behaves like a stablecoin / cash balance parked
  /// inside the investment account (e.g. COPW on Wenia). It still tracks a
  /// quantity so the user sees "how much liquid I have" and can swap it, but
  /// it's excluded from P&L, portfolio donut, and the "Invested" aggregate.
  final bool isCashEquivalent;

  final DateTime createdAt;
  final DateTime updatedAt;

  InvestmentHolding({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.symbol,
    this.name,
    required this.assetClass,
    this.currency = 'COP',
    required this.quantity,
    required this.avgCost,
    required this.currentPrice,
    this.priceUpdatedAt,
    this.notes,
    this.sourceSymbol,
    this.isCashEquivalent = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InvestmentHolding.fromJson(Map<String, dynamic> json) {
    return InvestmentHolding(
      id: json['id'],
      userId: json['user_id'],
      accountId: json['account_id'],
      symbol: json['symbol'],
      name: json['name'],
      assetClass: json['asset_class'],
      currency: json['currency'] ?? 'COP',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      avgCost: (json['avg_cost'] as num?)?.toDouble() ?? 0.0,
      currentPrice: (json['current_price'] as num?)?.toDouble() ?? 0.0,
      priceUpdatedAt: json['price_updated_at'] != null
          ? DateTime.parse(json['price_updated_at'])
          : null,
      notes: json['notes'],
      sourceSymbol: json['source_symbol'],
      isCashEquivalent: (json['is_cash_equivalent'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  /// Current market value of this position (quantity × currentPrice), in [currency].
  double get marketValue => quantity * currentPrice;

  /// Total cost basis (quantity × avgCost), in [currency].
  double get costBasis => quantity * avgCost;

  /// Unrealized P&L in [currency].
  double get unrealizedPnl => marketValue - costBasis;

  /// Unrealized P&L as a percentage of cost basis.
  double get unrealizedPnlPct =>
      costBasis == 0 ? 0 : (unrealizedPnl / costBasis) * 100;

  /// Display name: symbol if name is null.
  String get displayName => (name != null && name!.isNotEmpty) ? name! : symbol;
}
