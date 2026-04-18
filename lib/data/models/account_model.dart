import 'credit_card_rules_model.dart';
import 'investment_details_model.dart';
import 'savings_interest_details_model.dart';

class Account {
  final String id;
  final String name;
  final String type;
  final double balance;
  final double creditLimit;
  final double balanceUsd;
  final double creditLimitUsd;
  final double minimumPaymentCop;
  final double minimumPaymentUsd;
  final int? closingDay;
  final int? paymentDueDay;
  final CreditCardRules? creditCardRules;
  final InvestmentDetails? investmentDetails;
  final SavingsInterestDetails? interestDetails;
  final String? parentAccountId;
  final List<Account> pockets;
  final String? icon;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.creditLimit = 0.0,
    this.balanceUsd = 0.0,
    this.creditLimitUsd = 0.0,
    this.minimumPaymentCop = 0.0,
    this.minimumPaymentUsd = 0.0,
    this.closingDay,
    this.paymentDueDay,
    this.creditCardRules,
    this.investmentDetails,
    this.interestDetails,
    this.parentAccountId,
    this.pockets = const [],
    this.icon,
  });

  bool get isPocket => parentAccountId != null;
  bool get isSavingsParent => type == 'savings' && parentAccountId == null;
  bool get earnsInterest =>
      interestDetails?.apyRate != null && interestDetails!.apyRate! > 0;

  /// Sum of the pocket balances (COP). Zero if no pockets.
  double get pocketsBalance =>
      pockets.fold(0.0, (sum, p) => sum + p.balance);

  /// Combined balance for a savings parent: own balance + all pockets.
  /// Returns [balance] unchanged for non-parents.
  double get totalBalanceWithPockets => balance + pocketsBalance;

  factory Account.fromJson(Map<String, dynamic> json) {
    final rawPockets = json['pockets'];
    final pocketList = rawPockets is List
        ? rawPockets
            .map((p) => Account.fromJson(p as Map<String, dynamic>))
            .toList()
        : <Account>[];

    final rawInterest = json['savings_interest_details'];
    SavingsInterestDetails? interest;
    if (rawInterest is Map<String, dynamic>) {
      interest = SavingsInterestDetails.fromJson(rawInterest);
    } else if (rawInterest is List && rawInterest.isNotEmpty) {
      interest = SavingsInterestDetails.fromJson(
          rawInterest.first as Map<String, dynamic>);
    }

    return Account(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      creditLimit: (json['credit_limit'] as num?)?.toDouble() ?? 0.0,
      balanceUsd: (json['balance_usd'] as num?)?.toDouble() ?? 0.0,
      creditLimitUsd: (json['credit_limit_usd'] as num?)?.toDouble() ?? 0.0,
      minimumPaymentCop:
          (json['minimum_payment_cop'] as num?)?.toDouble() ?? 0.0,
      minimumPaymentUsd:
          (json['minimum_payment_usd'] as num?)?.toDouble() ?? 0.0,
      closingDay: json['closing_day'],
      paymentDueDay: json['payment_due_day'],
      icon: json['icon'],
      parentAccountId: json['parent_account_id'] as String?,
      pockets: pocketList,
      creditCardRules: json['credit_card_details'] != null
          ? CreditCardRules.fromJson(json['credit_card_details'])
          : null,
      investmentDetails: json['investment_details'] != null
          ? InvestmentDetails.fromJson(json['investment_details'])
          : null,
      interestDetails: interest,
    );
  }
}
