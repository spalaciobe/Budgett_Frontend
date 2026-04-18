/// A single closed sub-period within a savings-account interest cycle.
///
/// Represents a contiguous window where both [balance] and [apyRate] were
/// constant. The app appends one of these every time a deposit, withdrawal
/// or rate change is recorded against a savings account that earns interest,
/// capturing the balance/rate *before* the change.
///
/// [from] is inclusive; [to] is exclusive (start of the next segment).
class InterestPeriodSegment {
  final DateTime from;
  final DateTime to;
  final double balance;
  final double apyRate;

  const InterestPeriodSegment({
    required this.from,
    required this.to,
    required this.balance,
    required this.apyRate,
  });

  factory InterestPeriodSegment.fromJson(Map<String, dynamic> json) {
    return InterestPeriodSegment(
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      balance: (json['balance'] as num).toDouble(),
      apyRate: (json['apy'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'from':
            '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        'to':
            '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}',
        'balance': balance,
        'apy': apyRate,
      };
}

/// 1:1 extension of a savings account (parent or pocket) that earns interest.
/// Backed by the `savings_interest_details` table.
class SavingsInterestDetails {
  final String id;
  final String accountId;
  final double? apyRate;
  final String? interestPeriod;
  final DateTime? lastInterestDate;
  final List<InterestPeriodSegment> periodSegments;
  final String? notes;

  const SavingsInterestDetails({
    required this.id,
    required this.accountId,
    this.apyRate,
    this.interestPeriod,
    this.lastInterestDate,
    this.periodSegments = const [],
    this.notes,
  });

  factory SavingsInterestDetails.fromJson(Map<String, dynamic> json) {
    return SavingsInterestDetails(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      apyRate: (json['apy_rate'] as num?)?.toDouble(),
      interestPeriod: json['interest_period'] as String?,
      lastInterestDate: json['last_interest_date'] != null
          ? DateTime.parse(json['last_interest_date'] as String)
          : null,
      periodSegments: _parseSegments(json['period_segments']),
      notes: json['notes'] as String?,
    );
  }

  static List<InterestPeriodSegment> _parseSegments(dynamic raw) {
    if (raw == null) return const [];
    final list = raw as List<dynamic>;
    return list
        .map((e) => InterestPeriodSegment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  SavingsInterestDetails copyWith({
    double? apyRate,
    String? interestPeriod,
    DateTime? lastInterestDate,
    List<InterestPeriodSegment>? periodSegments,
    String? notes,
  }) {
    return SavingsInterestDetails(
      id: id,
      accountId: accountId,
      apyRate: apyRate ?? this.apyRate,
      interestPeriod: interestPeriod ?? this.interestPeriod,
      lastInterestDate: lastInterestDate ?? this.lastInterestDate,
      periodSegments: periodSegments ?? this.periodSegments,
      notes: notes ?? this.notes,
    );
  }
}
