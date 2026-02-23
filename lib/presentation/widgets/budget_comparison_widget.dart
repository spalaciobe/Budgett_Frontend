import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';

class BudgetComparisonWidget extends StatelessWidget {
  final String categoryName;
  final double budgetAmount;
  final double spentAmount;
  final Color? color;
  final bool isIncome;
  final String? iconName;
  final VoidCallback? onEditBudget;
  final VoidCallback? onEditCategory;

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
    this.subCategories,
    this.subCategorySpending,
  });

  final List<SubCategory>? subCategories;
  final Map<String, double>? subCategorySpending;

  @override
  Widget build(BuildContext context) {
    Widget buildIcon() {
      if (iconName != null && IconHelper.iconMap.containsKey(iconName)) {
        return Icon(IconHelper.iconMap[iconName], color: color ?? Colors.grey, size: 20);
      }
      return Text(iconName ?? '📁', style: const TextStyle(fontSize: 20));
    }

    if (budgetAmount <= 0) {
      // No budget set case
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onEditBudget,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _CategoryIconButton(
                  color: color,
                  iconName: iconName,
                  onTap: onEditCategory,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(categoryName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        isIncome ? 'No expected income set' : 'No budget set',
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

    final double progress = (spentAmount / budgetAmount).clamp(0.0, 1.0);
    final bool isOverBudget = spentAmount > budgetAmount;
    final bool isNearLimit = !isOverBudget && progress > 0.9;
    
    // Determine status color
    // For Income: usually Green is good. If we met target (spent >= budget), it's good.
    // But here 'spent' means 'actual income'.
    Color statusColor;
    if (isIncome) {
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: onEditBudget,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CategoryIconButton(
                    color: color,
                    iconName: iconName,
                    onTap: onEditCategory,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      categoryName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // amounts row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isIncome ? 'Earned' : 'Spent',
                        style: TextStyle(fontSize: 12, color: Colors.grey[200]),
                      ),
                      Text(
                        CurrencyFormatter.format(spentAmount, decimalDigits: 2),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: !isIncome && isOverBudget ? Theme.of(context).colorScheme.error : null,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isIncome ? 'Target' : 'Budget',
                        style: TextStyle(fontSize: 12, color: Colors.grey[200]),
                      ),
                      Text(
                        CurrencyFormatter.format(budgetAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
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
              
              const SizedBox(height: 8),
              
              // Status message
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isIncome
                       ? ((isOverBudget || progress >= 1) ? Icons.check_circle : Icons.trending_up)
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
                        isIncome
                          ? ((isOverBudget || progress >= 1)
                              ? 'Target reached!'
                              : '${CurrencyFormatter.format(budgetAmount - spentAmount, decimalDigits: 2)} to go')
                          : (isOverBudget 
                              ? 'Over budget by ${CurrencyFormatter.format(spentAmount - budgetAmount, decimalDigits: 2)}'
                              : '${CurrencyFormatter.format(budgetAmount - spentAmount, decimalDigits: 2)} remaining'),
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
              
              if (subCategories != null && subCategories!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: subCategories!.map((sub) {
                      final amount = subCategorySpending?[sub.id] ?? 0.0;
                      // Only show if amount > 0 for cleanliness, or always show?
                      // Showing always allows user to see what they have.
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 12.0),
                              child: Text(
                                sub.name, 
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(amount, decimalDigits: 2),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
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
      if (widget.iconName != null && IconHelper.iconMap.containsKey(widget.iconName)) {
        return Icon(
          IconHelper.iconMap[widget.iconName], 
          color: widget.color ?? Colors.grey, 
          size: 20
        );
      }
      return Text(widget.iconName ?? '📁', style: const TextStyle(fontSize: 20));
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          widget.onTap?.call();
        },
        child: CircleAvatar(
          backgroundColor: widget.color?.withOpacity(0.5) ?? Colors.grey.withOpacity(0.5),
          radius: 16,
          child: _isHovered 
            ? const Icon(Icons.more_horiz, color: Colors.white, size: 20)
            : buildIcon(),
        ),
      ),
    );
  }
}
