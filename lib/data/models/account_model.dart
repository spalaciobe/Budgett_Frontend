import 'credit_card_rules_model.dart';
import 'investment_details_model.dart';

class Account {
  final String id;
  final String name;
  final String type;
  final double balance;
  final double creditLimit;
  final double balanceUsd;
  final double creditLimitUsd;
  final int? closingDay;
  final int? paymentDueDay;
  final CreditCardRules? creditCardRules;
  final InvestmentDetails? investmentDetails;
  final String? icon;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.creditLimit = 0.0,
    this.balanceUsd = 0.0,
    this.creditLimitUsd = 0.0,
    this.closingDay,
    this.paymentDueDay,
    this.creditCardRules,
    this.investmentDetails,
    this.icon,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      creditLimit: (json['credit_limit'] as num?)?.toDouble() ?? 0.0,
      balanceUsd: (json['balance_usd'] as num?)?.toDouble() ?? 0.0,
      creditLimitUsd: (json['credit_limit_usd'] as num?)?.toDouble() ?? 0.0,
      closingDay: json['closing_day'],
      paymentDueDay: json['payment_due_day'],
      icon: json['icon'],
      creditCardRules: json['credit_card_details'] != null
          ? CreditCardRules.fromJson(json['credit_card_details'])
          : null,
      investmentDetails: json['investment_details'] != null
          ? InvestmentDetails.fromJson(json['investment_details'])
          : null,
    );
  }
}
