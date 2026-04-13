enum InvestmentType {
  highYield,
  cdt,
  fic,
  crypto,
  stockEtf;

  static InvestmentType fromString(String value) {
    switch (value) {
      case 'high_yield':
        return InvestmentType.highYield;
      case 'cdt':
        return InvestmentType.cdt;
      case 'fic':
        return InvestmentType.fic;
      case 'crypto':
        return InvestmentType.crypto;
      case 'stock_etf':
        return InvestmentType.stockEtf;
      default:
        return InvestmentType.highYield;
    }
  }

  String toDbString() {
    switch (this) {
      case InvestmentType.highYield:
        return 'high_yield';
      case InvestmentType.cdt:
        return 'cdt';
      case InvestmentType.fic:
        return 'fic';
      case InvestmentType.crypto:
        return 'crypto';
      case InvestmentType.stockEtf:
        return 'stock_etf';
    }
  }

  String get displayName {
    switch (this) {
      case InvestmentType.highYield:
        return 'High-Yield Savings';
      case InvestmentType.cdt:
        return 'CDT / Term Deposit';
      case InvestmentType.fic:
        return 'FIC / Mutual Fund';
      case InvestmentType.crypto:
        return 'Crypto';
      case InvestmentType.stockEtf:
        return 'Stocks & ETFs';
    }
  }

  /// True when the account holds multiple tradeable positions (not a single balance).
  bool get isMultiHolding =>
      this == InvestmentType.fic ||
      this == InvestmentType.crypto ||
      this == InvestmentType.stockEtf;
}

class InvestmentDetails {
  final String id;
  final String accountId;
  final String? brokerId;
  final InvestmentType investmentType;
  final String baseCurrency;

  // High-yield
  final double? apyRate;
  final String? interestPeriod;

  // CDT
  final double? principal;
  final double? interestRate;
  final int? termDays;
  final DateTime? startDate;
  final DateTime? maturityDate;
  final bool autoRenew;

  // FIC
  final String? fundCode;
  final String? navCurrency;

  final String? notes;

  InvestmentDetails({
    required this.id,
    required this.accountId,
    this.brokerId,
    required this.investmentType,
    this.baseCurrency = 'COP',
    this.apyRate,
    this.interestPeriod,
    this.principal,
    this.interestRate,
    this.termDays,
    this.startDate,
    this.maturityDate,
    this.autoRenew = false,
    this.fundCode,
    this.navCurrency,
    this.notes,
  });

  factory InvestmentDetails.fromJson(Map<String, dynamic> json) {
    return InvestmentDetails(
      id: json['id'],
      accountId: json['account_id'],
      brokerId: json['broker_id'],
      investmentType: InvestmentType.fromString(json['investment_type'] ?? 'high_yield'),
      baseCurrency: json['base_currency'] ?? 'COP',
      apyRate: (json['apy_rate'] as num?)?.toDouble(),
      interestPeriod: json['interest_period'],
      principal: (json['principal'] as num?)?.toDouble(),
      interestRate: (json['interest_rate'] as num?)?.toDouble(),
      termDays: json['term_days'] as int?,
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'])
          : null,
      maturityDate: json['maturity_date'] != null
          ? DateTime.parse(json['maturity_date'])
          : null,
      autoRenew: json['auto_renew'] ?? false,
      fundCode: json['fund_code'],
      navCurrency: json['nav_currency'],
      notes: json['notes'],
    );
  }
}
