import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_text.dart';
import '../../core/app_theme.dart';
import '../../data/models/transaction_model.dart';
import '../utils/currency_formatter.dart';

/// Standardized transaction row used across account detail views
/// (credit card, investment, savings / checking / cash).
///
/// Handles pending status visually: strike-through description, grey colors,
/// and a "Pending" badge next to the date. Also renders an optional extra
/// subtitle line for `place` and a cross-currency payment note when applicable.
class TransactionTile extends StatelessWidget {
  final Transaction transaction;

  /// Show a `+` or `−` prefix on the amount and colorize by type.
  /// Set `false` in contexts where sign is implicit (e.g. a billing-period
  /// card listing credit-card charges).
  final bool showSign;

  /// Which account's perspective drives sign/color for transfers.
  /// If `transaction.targetAccountId == perspectiveAccountId`, the transfer
  /// is treated as incoming (positive). Defaults to `transaction.accountId`
  /// (outgoing). Ignored for income/expense rows.
  final String? perspectiveAccountId;

  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.showSign = true,
    this.perspectiveAccountId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final theme = Theme.of(context);
    final isPending = t.status == 'pending';

    final bool isPositive;
    if (t.type == 'transfer') {
      final perspective = perspectiveAccountId ?? t.accountId;
      isPositive = t.targetAccountId == perspective;
    } else {
      isPositive = t.type == 'income';
    }
    final isTransfer = t.type == 'transfer';

    final Color typeColor;
    if (isTransfer) {
      typeColor = theme.colorScheme.secondary;
    } else if (isPositive) {
      typeColor = context.semantic.positive;
    } else {
      typeColor = theme.colorScheme.error;
    }

    final dotColor = isPending
        ? context.semantic.warning.withValues(alpha: 0.6)
        : typeColor.withValues(alpha: 0.6);

    final String sign;
    if (!showSign || isTransfer) {
      sign = '';
    } else {
      sign = isPositive ? '+' : '−';
    }

    final amountText =
        '$sign${CurrencyFormatter.format(t.amount, currency: t.currency)}';

    final amountColor = isPending ? Colors.grey : typeColor;

    final extraLines = <Widget>[];
    if (t.place != null && t.place!.isNotEmpty) {
      extraLines.add(Text(
        t.place!,
        style: AppText.caption.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        maxLines: 1,
        overflow: TextOverflow.fade,
      ));
    }
    if (t.isCrossCurrencyPayment && t.fxRate != null) {
      extraLines.add(Text(
        'Payment in COP @ \$${NumberFormat('#,###', 'en_US').format(t.fxRate!.toInt())}',
        style: AppText.caption.copyWith(color: context.semantic.positive),
      ));
    }

    final typeWord =
        isTransfer ? 'Transfer' : (isPositive ? 'Income' : 'Expense');
    final semanticsLabel = [
      typeWord,
      t.description,
      amountText,
      if (isPending) 'pending'
    ].join(', ');

    return Semantics(
      label: semanticsLabel,
      button: onTap != null,
      excludeSemantics: true,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 4,
          backgroundColor: dotColor,
        ),
        title: Text(
          t.description,
          style: AppText.tileTitle.copyWith(
            decoration: isPending ? TextDecoration.lineThrough : null,
            color: isPending ? Colors.grey : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.fade,
        ),
        trailing: Text(
          amountText,
          style: AppText.amount.copyWith(color: amountColor),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  DateFormat('d MMM', 'en').format(t.date),
                  style: AppText.caption,
                ),
                if (isPending) const _PendingBadge(),
              ],
            ),
            ...extraLines,
          ],
        ),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    final warning = context.semantic.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Pending',
        style: AppText.badge.copyWith(color: warning),
      ),
    );
  }
}
