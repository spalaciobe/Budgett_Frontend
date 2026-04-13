import 'package:flutter/material.dart';
import '../../data/models/account_model.dart';
import '../utils/currency_formatter.dart';

/// Horizontal account card used in the HomeScreen account strip.
///
/// [subtitle] is an optional pre-computed widget shown below the balance
/// (e.g. APY for high-yield, days-to-maturity for CDTs, type label for
/// multi-holding accounts). When null and the account is a credit card with a
/// USD balance, the USD balance is shown instead.
class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;
  final Widget? subtitle;

  const AccountCard({
    super.key,
    required this.account,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acc = account;

    // For USD-based investment accounts use the USD balance as the primary value.
    final isUsdInvestment =
        acc.type == 'investment' &&
        (acc.investmentDetails?.baseCurrency ?? 'COP') == 'USD';

    final balanceText = isUsdInvestment
        ? CurrencyFormatter.format(acc.balanceUsd, currency: 'USD')
        : CurrencyFormatter.format(acc.balance, decimalDigits: 2);

    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 170,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ],
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildIcon(acc, theme),
              ),

              // Name + balance + subtitle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    acc.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    balanceText,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    subtitle!,
                  ] else if (acc.type == 'credit_card' &&
                      acc.balanceUsd != 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(acc.balanceUsd, currency: 'USD'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Account acc, ThemeData theme) {
    final iconValue = acc.icon;
    if (iconValue != null && iconValue.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          iconValue,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            _iconForType(acc.type),
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
      );
    }
    return Center(
      child: Icon(
        _iconForType(acc.type),
        color: theme.colorScheme.primary,
        size: 20,
      ),
    );
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'credit_card':
        return Icons.credit_card;
      case 'cash':
        return Icons.money;
      case 'investment':
        return Icons.trending_up;
      case 'savings':
        return Icons.savings;
      default:
        return Icons.account_balance;
    }
  }
}
