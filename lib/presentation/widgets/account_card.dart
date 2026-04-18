import 'package:flutter/material.dart';
import '../../core/app_spacing.dart';
import '../../data/models/account_model.dart';
import '../utils/currency_formatter.dart';

/// Account card shown in the HomeScreen accounts section.
///
/// [subtitle] is an optional pre-computed widget shown below the balance
/// (e.g. gains for investment accounts, USD balance for credit cards).
///
/// [balanceText] overrides the default balance display computed from
/// [account.balance] / [account.balanceUsd]. Use this to show a pre-computed
/// value such as total investment portfolio value (cash + holdings).
///
/// [tileLayout] switches to a full-width horizontal tile (icon left, text
/// right) used on mobile. When false (default) the card renders as a compact
/// vertical card for the horizontal scroll strip on desktop/tablet.
class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;
  final Widget? subtitle;
  final String? balanceText;
  final bool tileLayout;

  const AccountCard({
    super.key,
    required this.account,
    required this.onTap,
    this.subtitle,
    this.balanceText,
    this.tileLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acc = account;

    final isUsdInvestment =
        acc.type == 'investment' &&
        (acc.investmentDetails?.baseCurrency ?? 'COP') == 'USD';
    final isSavingsWithPockets =
        acc.isSavingsParent && acc.pockets.isNotEmpty;

    final balanceDisplay = balanceText ??
        (isUsdInvestment
            ? CurrencyFormatter.format(acc.balanceUsd, currency: 'USD')
            : isSavingsWithPockets
                ? CurrencyFormatter.format(
                    acc.totalBalanceWithPockets,
                    decimalDigits: 2,
                  )
                : CurrencyFormatter.format(acc.balance, decimalDigits: 2));

    final gradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          theme.colorScheme.surface,
          theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        ],
      ),
    );

    final iconWidget = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _buildIcon(acc, theme),
    );

    final hasSubtitleContent = subtitle != null ||
        (acc.type == 'credit_card' && acc.balanceUsd != 0) ||
        isSavingsWithPockets;
    final pocketLabel = acc.pockets.length == 1 ? 'pocket' : 'pockets';
    final subtitleArea = hasSubtitleContent
        ? (subtitle ??
            (isSavingsWithPockets
                ? Text(
                    '${acc.pockets.length} $pocketLabel · '
                    '${CurrencyFormatter.format(acc.pocketsBalance, decimalDigits: 2)} stored',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  )
                : Text(
                    CurrencyFormatter.format(acc.balanceUsd, currency: 'USD'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  )))
        : const SizedBox.shrink();

    final textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          acc.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          balanceDisplay,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 2),
        subtitleArea,
      ],
    );

    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: tileLayout
            ? Container(
                decoration: gradient,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: kSpaceLg,
                ),
                child: Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 14),
                    Expanded(child: textContent),
                  ],
                ),
              )
            : Container(
                width: 170,
                decoration: gradient,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [iconWidget, textContent],
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
