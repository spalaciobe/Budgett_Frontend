import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import '../../core/app_text.dart';

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

  /// Budget per sub-category for the month, keyed by sub-category id.
  final Map<String, double>? subCategoryBudgets;

  /// True when [budgetAmount] is just the sum of the sub-category budgets
  /// (no larger category-level budget overrides it).
  final bool budgetFromSubcategories;

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
    this.subCategoryBudgets,
    this.budgetFromSubcategories = false,
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
                            overflow: TextOverflow.fade,
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
                            CurrencyFormatter.format(widget.spentAmount),
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
                                ? '${CurrencyFormatter.format(widget.spentAmount)} earned — set a target to track progress'
                                : widget.isSavings
                                    ? '${CurrencyFormatter.format(widget.spentAmount)} contributed — set a monthly target to track progress'
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

    // Money in the category budget not assigned to any sub-category, and the
    // spending that isn't covered by a sub-category budget (either untagged
    // or tagged with a sub-category without its own budget).
    final subBudgets = widget.subCategoryBudgets ?? const <String, double>{};
    final double assigned =
        subBudgets.values.fold<double>(0.0, (sum, v) => sum + v);
    final double unassigned = subBudgets.isEmpty
        ? 0.0
        : (widget.budgetAmount - assigned).clamp(0.0, double.infinity);
    final double spentInBudgetedSubs = subBudgets.keys.fold<double>(
        0.0, (sum, id) => sum + (widget.subCategorySpending?[id] ?? 0.0));
    final double unassignedSpent = (widget.spentAmount - spentInBudgetedSubs)
        .clamp(0.0, double.infinity);

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
                              CurrencyFormatter.format(widget.spentAmount),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
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
                              overflow: TextOverflow.fade,
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              CurrencyFormatter.format(widget.budgetAmount),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (widget.budgetFromSubcategories)
                              Text(
                                'Sum of subcategories',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
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
                                    : '${CurrencyFormatter.format(widget.budgetAmount - widget.spentAmount)} to go')
                                : (isOverBudget
                                    ? 'Over budget by ${CurrencyFormatter.format(widget.spentAmount - widget.budgetAmount)}'
                                    : '${CurrencyFormatter.format(widget.budgetAmount - widget.spentAmount)} remaining'),
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
                          CurrencyFormatter.format(widget.accumulatedBalance!),
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
                        children: [
                          for (final sub in widget.subCategories!)
                            _SubCategoryRow(
                              name: sub.name,
                              spent:
                                  widget.subCategorySpending?[sub.id] ?? 0.0,
                              budget: widget.subCategoryBudgets?[sub.id],
                              isIncome: widget.isIncome,
                            ),
                          if (unassigned > 0)
                            _SubCategoryRow(
                              name: 'Unassigned',
                              spent: unassignedSpent,
                              budget: unassigned,
                              isIncome: widget.isIncome,
                              italic: true,
                            ),
                        ],
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

/// One sub-category line inside an expanded category card: its spending and,
/// when it has its own budget, "spent / budget" plus a thin progress bar.
class _SubCategoryRow extends StatelessWidget {
  final String name;
  final double spent;
  final double? budget;
  final bool isIncome;
  final bool italic;

  const _SubCategoryRow({
    required this.name,
    required this.spent,
    required this.budget,
    required this.isIncome,
    this.italic = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBudget = budget != null && budget! > 0;
    final over = hasBudget && spent > budget!;
    final progress = hasBudget ? (spent / budget!).clamp(0.0, 1.0) : 0.0;
    final Color barColor = isIncome
        ? (progress >= 1.0 ? context.semantic.positive : context.semantic.warning)
        : over
            ? scheme.error
            : progress > 0.9
                ? context.semantic.warning
                : scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 3, bottom: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontStyle: italic ? FontStyle.italic : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: CurrencyFormatter.format(spent),
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: !isIncome && over ? scheme.error : null,
                      ),
                    ),
                    if (hasBudget)
                      TextSpan(
                        text: ' / ${CurrencyFormatter.format(budget!)}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          if (hasBudget) ...[
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: scheme.surfaceContainerHighest,
                color: barColor,
                minHeight: 3,
              ),
            ),
          ],
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
          color: widget.color ?? context.muted,
          size: 20,
        );
      }
      return Text(widget.iconName ?? '📁',
          style: AppText.balance);
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
              widget.color?.withValues(alpha: 0.5) ?? context.muted.withValues(alpha: 0.5),
          radius: 16,
          child: _isHovered
              ? const Icon(Icons.more_horiz, color: Colors.white, size: 20)
              : buildIcon(),
        ),
      ),
    );
  }
}
