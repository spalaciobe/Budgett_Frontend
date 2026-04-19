import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';

class BudgetComparisonWidget extends StatefulWidget {
  final String categoryName;
  final double budgetAmount;
  final double spentAmount;
  final Color? color;
  final bool isIncome;
  /// True when this row represents a sinking-fund category. Re-labels
  /// "Spent/Budget" → "Contributed/Monthly target" and renders [accumulatedBalance].
  final bool isSavings;
  final double? accumulatedBalance;
  final String? iconName;
  final VoidCallback? onEditBudget;
  final VoidCallback? onEditCategory;
  final List<SubCategory>? subCategories;
  final Map<String, double>? subCategorySpending;

  const BudgetComparisonWidget({
    super.key,
    required this.categoryName,
    required this.budgetAmount,
    required this.spentAmount,
    this.color,
    this.iconName,
    this.onEditBudget,
    this.onEditCategory,
    this.isIncome = false,
    this.isSavings = false,
    this.accumulatedBalance,
    this.subCategories,
    this.subCategorySpending,
  });

  @override
  State<BudgetComparisonWidget> createState() => _BudgetComparisonWidgetState();
}

class _BudgetComparisonWidgetState extends State<BudgetComparisonWidget> {
  bool _expanded = true;
  bool _subExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.budgetAmount <= 0) {
      // No budget set case — always show, no collapse needed
      return Card(
        margin: const EdgeInsets.only(bottom: kSpaceLg),
        child: InkWell(
          onTap: widget.onEditBudget,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: kCardPadding,
            child: Row(
              children: [
                _CategoryIconButton(
                  color: widget.color,
                  iconName: widget.iconName,
                  onTap: widget.onEditCategory,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.categoryName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isIncome
                            ? 'No expected income set'
                            : widget.isSavings
                                ? 'No monthly target set'
                                : 'No budget set',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.add_circle_outline, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      );
    }

    final double progress =
        (widget.spentAmount / widget.budgetAmount).clamp(0.0, 1.0);
    final bool isOverBudget = widget.spentAmount > widget.budgetAmount;
    final bool isNearLimit = !isOverBudget && progress > 0.9;

    Color statusColor;
    if (widget.isIncome) {
      statusColor = isOverBudget || progress >= 1.0
          ? Colors.green
          : Colors.orange;
    } else {
      statusColor = isOverBudget
          ? Theme.of(context).colorScheme.error
          : isNearLimit
              ? Colors.orange
              : Theme.of(context).colorScheme.primary;
    }

    final bool hasSubs = widget.subCategories != null &&
        widget.subCategories!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: kSpaceLg),
      elevation: 2,
      child: Column(
        children: [
          // ── Header row (always visible) ──────────────────────────────────
          InkWell(
            onTap: widget.onEditBudget,
            borderRadius: _expanded
                ? const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  )
                : BorderRadius.circular(12),
            child: Padding(
              padding: kCardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CategoryIconButton(
                        color: widget.color,
                        iconName: widget.iconName,
                        onTap: widget.onEditCategory,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.categoryName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      if (!_expanded)
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  // Slim progress bar visible when collapsed
                  if (!_expanded) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade200,
                        color: statusColor,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Expandable detail ─────────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSpaceXl, 0, kSpaceXl, kSpaceXl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Amounts row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isIncome
                                ? 'Earned'
                                : widget.isSavings
                                    ? 'Contributed'
                                    : 'Spent',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[200]),
                          ),
                          Text(
                            CurrencyFormatter.format(widget.spentAmount,
                                decimalDigits: 2),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: !widget.isIncome &&
                                      !widget.isSavings &&
                                      isOverBudget
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.isIncome
                                ? 'Target'
                                : widget.isSavings
                                    ? 'Monthly target'
                                    : 'Budget',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[200]),
                          ),
                          Text(
                            CurrencyFormatter.format(widget.budgetAmount),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),

                  kGapMd,

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      color: statusColor,
                      minHeight: 8,
                    ),
                  ),

                  kGapMd,

                  // Status message
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.isIncome
                              ? ((isOverBudget || progress >= 1)
                                  ? Icons.check_circle
                                  : Icons.trending_up)
                              : (isOverBudget
                                  ? Icons.warning_amber_rounded
                                  : isNearLimit
                                      ? Icons.info_outline
                                      : Icons.check_circle_outline),
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.isIncome
                                ? ((isOverBudget || progress >= 1)
                                    ? 'Target reached!'
                                    : '${CurrencyFormatter.format(widget.budgetAmount - widget.spentAmount, decimalDigits: 2)} to go')
                                : (isOverBudget
                                    ? 'Over budget by ${CurrencyFormatter.format(widget.spentAmount - widget.budgetAmount, decimalDigits: 2)}'
                                    : '${CurrencyFormatter.format(widget.budgetAmount - widget.spentAmount, decimalDigits: 2)} remaining'),
                            style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[200],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sinking-fund accumulated balance footer.
                  if (widget.isSavings && widget.accumulatedBalance != null) ...[
                    kGapMd,
                    Row(
                      children: [
                        Icon(Icons.savings_outlined,
                            size: 14, color: Colors.grey[300]),
                        const SizedBox(width: 4),
                        Text(
                          'Fund balance: ',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[200]),
                        ),
                        Text(
                          CurrencyFormatter.format(widget.accumulatedBalance!,
                              decimalDigits: 2),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: widget.accumulatedBalance! < 0
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Subcategories section
                  if (hasSubs) ...[
                    const SizedBox(height: kSpaceLg),
                    // Subcategory header with collapse toggle
                    GestureDetector(
                      onTap: () =>
                          setState(() => _subExpanded = !_subExpanded),
                      child: Row(
                        children: [
                          Text(
                            'Subcategories',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _subExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4),
                          ),
                        ],
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 180),
                      crossFadeState: _subExpanded
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Column(
                        children: widget.subCategories!.map((sub) {
                          final amount =
                              widget.subCategorySpending?[sub.id] ?? 0.0;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 12.0),
                                  child: Text(
                                    sub.name,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey),
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(amount,
                                      decimalDigits: 2),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      secondChild: const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _CategoryIconButton extends StatefulWidget {
  final Color? color;
  final String? iconName;
  final VoidCallback? onTap;

  const _CategoryIconButton({
    this.color,
    this.iconName,
    this.onTap,
  });

  @override
  State<_CategoryIconButton> createState() => _CategoryIconButtonState();
}

class _CategoryIconButtonState extends State<_CategoryIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget buildIcon() {
      if (widget.iconName != null &&
          IconHelper.iconMap.containsKey(widget.iconName)) {
        return Icon(
          IconHelper.iconMap[widget.iconName],
          color: widget.color ?? Colors.grey,
          size: 20,
        );
      }
      return Text(widget.iconName ?? '📁',
          style: const TextStyle(fontSize: 20));
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          widget.onTap?.call();
        },
        child: CircleAvatar(
          backgroundColor:
              widget.color?.withOpacity(0.5) ?? Colors.grey.withOpacity(0.5),
          radius: 16,
          child: _isHovered
              ? const Icon(Icons.more_horiz, color: Colors.white, size: 20)
              : buildIcon(),
        ),
      ),
    );
  }
}
