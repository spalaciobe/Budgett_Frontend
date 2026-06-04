import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/widgets/transaction_tile.dart';

/// Lists the transactions that make up a category's total for a given month,
/// opened from the magnifying-glass button on each Budget-screen category card.
/// The footer total reconciles with the card's headline (reimbursements are
/// subtracted for expense categories).
class CategoryTransactionsDialog extends ConsumerWidget {
  final String categoryId;
  final String categoryName;
  final String categoryType; // 'expense' | 'income' | 'savings'
  final int month;
  final int year;

  const CategoryTransactionsDialog({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryType,
    required this.month,
    required this.year,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(categoryMonthTransactionsProvider(
      (categoryId: categoryId, month: month, year: year, type: categoryType),
    ));

    final totalLabel = categoryType == 'income'
        ? 'Earned'
        : categoryType == 'savings'
            ? 'Contributed'
            : 'Spent';

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: kDialogPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryName,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_months[month - 1]} $year',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: transactionsAsync.when(
                data: (transactions) {
                  if (transactions.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 48, color: Colors.grey[600]),
                            kGapMd,
                            Text(
                              'No transactions this month',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Net of reimbursements (income rows) so the footer matches
                  // the card's headline.
                  final net = transactions.fold<double>(0.0, (sum, t) {
                    final signed = t.type == 'income' ? -t.amount : t.amount;
                    return sum + signed;
                  });

                  return Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: transactions.length,
                          itemBuilder: (_, i) =>
                              TransactionTile(transaction: transactions[i]),
                        ),
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$totalLabel · ${transactions.length} '
                              '${transactions.length == 1 ? 'transaction' : 'transactions'}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              CurrencyFormatter.format(net, decimalDigits: 0),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text(friendlyError(e))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
