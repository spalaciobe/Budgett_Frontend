import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

import 'package:budgett_frontend/core/app_theme.dart';
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
  /// Opens the list of this category's transactions for the selected month
  /// (the magnifying-glass button in the header).
  final VoidCallback? onViewTransactions;
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
    this.onViewTransactions,
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
  // Cards start collapsed so the list shows an overview (name + slim bar + %)
  // and the Financial Health summary stays in view; tap a card to expand it.
  bool _expanded = false;
  bool _subExpanded = true;

  /// Magnifying-glass button that opens this category's transactions for the
  /// month. Absorbs its own tap so it doesn't trigger the header's edit-budget
  /// InkWell.
  Widget _viewTransactionsButton(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      iconSize: 18,
      tooltip: 'View transactions',
      icon: Icon(
        Icons.search,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      onPressed: widget.onViewTransactions,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.budgetAmount <= 0) {
      // No budget set — still surface actual activity (spent / earned /
      // contributed) so the user can see where money is going even before
      // setting a target.
      final hasActivity = widget.spentAmount > 0;
      final activityLabel = widget.isIncome
          ? 'Earned'
          : widget.isSavings
              ? 'Contributed'
              : 'Spent';
      final emptyLabel = widget.isIncome
          ? 'No expected income set'
          : widget.isSavings
              ? 'No monthly target set'
              : 'No budget set';
      final activityColor = widget.isIncome
          ? context.semantic.positive
          : widget.isSavings
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error;

      return Card(
        margin: const EdgeInsets.only(bottom: kSpaceLg),
        child: InkWell(
          onTap: widget.onEditBudget,
          borderRadius: BorderRadius.circular(12),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.categoryName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            emptyLabel,
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (hasActivity && widget.onViewTransactions != null) ...[
                      _viewTransactionsButton(context),
                      const SizedBox(width: 4),
                    ],
                    if (hasActivity)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            activityLabel,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                          Text(
                            CurrencyFormatter.format(widget.spentAmount,
                                decimalDigits: 0),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: activityColor,
                            ),
                          ),
                        ],
                      )
                    else
                      Icon(Icons.add_circle_outline,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
                if (hasActivity) ...[
                  kGapMd,
                  // Full-width bar in activity color so it's visually
                  // consistent with the with-budget card. Saturated solid
                  // colour (no budget reference to scale against).
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 1.0,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      color: activityColor,
                      minHeight: 6,
                    ),
                  ),
                  kGapXs,
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: activityColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.isIncome
                              ? Icons.trending_up
                              : widget.isSavings
                                  ? Icons.savings_outlined
                                  : Icons.warning_amber_rounded,
                          size: 12,
                          color: activityColor,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.isIncome
                                ? '${CurrencyFormatter.format(widget.spentAmount, decimalDigits: 0)} earned — set a target to track progress'
                                : widget.isSavings
                                    ? '${CurrencyFormatter.format(widget.spentAmount, decimalDigits: 0)} contributed — set a monthly target to track progress'
                                    : 'Spent without a budget — tap to set one',
                            style: TextStyle(
                              fontSize: 11,
                              color: activityColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
          ? context.semantic.positive
          : context.semantic.warning;
    } else {
      statusColor = isOverBudget
          ? Theme.of(context).colorScheme.error
          : isNearLimit
              ? context.semantic.warning
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
            onTap: () => setState(() => _expanded = !_expanded),
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
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 44, minHeight: 44),
                        iconSize: 18,
                        tooltip: 'Edit budget',
                        onPressed: widget.onEditBudget,
                        icon: Icon(
                          Icons.edit_outlined,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      if (widget.onViewTransactions != null)
                        _viewTransactionsButton(context),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 44, minHeight: 44),
                        iconSize: 20,
                        tooltip: _expanded ? 'Collapse' : 'Expand',
                        onPressed: () =>
                            setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
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
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
                  // Amounts row. Both columns are Flexible with ellipsis so
                  // large COP amounts can't overflow on narrow phones.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isIncome
                                  ? 'Earned'
                                  : widget.isSavings
                                      ? 'Contributed'
                                      : 'Spent',
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              CurrencyFormatter.format(widget.spentAmount,
                                  decimalDigits: 0),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.isIncome
                                  ? 'Target'
                                  : widget.isSavings
                                      ? 'Monthly target'
                                      : 'Budget',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              CurrencyFormatter.format(widget.budgetAmount),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  kGapMd,

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
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
                      color: statusColor.withValues(alpha: 0.1),
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
                                    : '${CurrencyFormatter.format(widget.budgetAmount - widget.spentAmount, decimalDigits: 0)} to go')
                                : (isOverBudget
                                    ? 'Over budget by ${CurrencyFormatter.format(widget.spentAmount - widget.budgetAmount, decimalDigits: 0)}'
                                    : '${CurrencyFormatter.format(widget.budgetAmount - widget.spentAmount, decimalDigits: 0)} remaining'),
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            size: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Fund balance: ',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          CurrencyFormatter.format(widget.accumulatedBalance!,
                              decimalDigits: 0),
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
                    InkWell(
                      onTap: () =>
                          setState(() => _subExpanded = !_subExpanded),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
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
                                    .withValues(alpha: 0.5),
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
                                  .withValues(alpha: 0.4),
                            ),
                          ],
                        ),
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
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(amount,
                                      decimalDigits: 0),
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
              widget.color?.withValues(alpha: 0.5) ?? Colors.grey.withValues(alpha: 0.5),
          radius: 16,
          child: _isHovered
              ? const Icon(Icons.more_horiz, color: Colors.white, size: 20)
              : buildIcon(),
        ),
      ),
    );
  }
}
