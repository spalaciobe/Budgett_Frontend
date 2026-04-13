class FxRate {
  final String id;
  final String base;
  final String quote;
  final double rate;
  final DateTime asOfDate;
  final String source;
  final DateTime fetchedAt;

  /// True when the rate was fetched on a previous day and the network
  /// was unavailable to refresh it for today.
  final bool isStale;

  FxRate({
    required this.id,
    required this.base,
    required this.quote,
    required this.rate,
    required this.asOfDate,
    required this.source,
    required this.fetchedAt,
    this.isStale = false,
  });

  factory FxRate.fromJson(Map<String, dynamic> json, {bool isStale = false}) {
    return FxRate(
      id: json['id'],
      base: json['base'],
      quote: json['quote'],
      rate: (json['rate'] as num).toDouble(),
      asOfDate: DateTime.parse(json['as_of_date']),
      source: json['source'],
      fetchedAt: DateTime.parse(json['fetched_at']),
      isStale: isStale,
    );
  }

  /// Convert [amountBase] (in [base] currency) to [quote] currency.
  double convert(double amountBase) => amountBase * rate;
}
