import 'package:flutter/material.dart';
import '../../core/app_spacing.dart';
import '../../data/models/investment_holding_model.dart';
import '../utils/currency_formatter.dart';

/// Card displaying a single investment holding with quantity, cost, price,
/// market value, P&L, and an action menu (Buy, Sell, Edit, Delete).
class InvestmentHoldingCard extends StatelessWidget {
  final InvestmentHolding holding;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const InvestmentHoldingCard({
    super.key,
    required this.holding,
    required this.onBuy,
    required this.onSell,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pnl = holding.unrealizedPnl;
    final pnlPct = holding.unrealizedPnlPct;
    final isPositive = pnl >= 0;
    final pnlColor =
        isPositive ? Colors.green.shade600 : theme.colorScheme.error;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: kSpaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Symbol + asset class chip
                Row(
                  children: [
                    Text(
                      holding.symbol,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(
                        holding.assetClass.toUpperCase(),
                        style: theme.textTheme.labelSmall,
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                // Action menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'buy', child: Text('Buy')),
                    const PopupMenuItem(value: 'sell', child: Text('Sell')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                  onSelected: (v) {
                    switch (v) {
                      case 'buy':
                        onBuy();
                      case 'sell':
                        onSell();
                      case 'edit':
                        onEdit();
                      case 'delete':
                        onDelete();
                    }
                  },
                ),
              ],
            ),

            if (holding.name != null && holding.name!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                holding.name!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],

            kGapLg,

            // Quantity row
            Row(
              children: [
                Flexible(
                  child: _InfoChip(
                    label: 'Qty',
                    value: CurrencyFormatter.formatQuantity(holding.quantity),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: _InfoChip(
                    label: 'Avg cost',
                    value: CurrencyFormatter.format(holding.avgCost,
                        currency: holding.currency),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: _InfoChip(
                    label: 'Price',
                    value: CurrencyFormatter.format(holding.currentPrice,
                        currency: holding.currency),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: kSpaceMd),
              child: const Divider(height: 1),
            ),

            // Value + P&L row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Market Value',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.6),
                          )),
                      Text(
                        CurrencyFormatter.format(holding.marketValue,
                            currency: holding.currency),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Unrealized P&L',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.6),
                          )),
                      Text(
                        '${isPositive ? '+' : ''}${CurrencyFormatter.format(pnl, currency: holding.currency)} '
                        '(${isPositive ? '+' : ''}${pnlPct.toStringAsFixed(2)}%)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: pnlColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.55))),
        Text(value,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
