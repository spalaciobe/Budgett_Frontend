import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

import 'package:budgett_frontend/presentation/utils/icon_helper.dart';

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
  });

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
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color?.withOpacity(0.1) ?? Colors.grey.withOpacity(0.1),
            child: buildIcon(),
          ),
          title: Text(categoryName),
          subtitle: Text(isIncome ? 'No expected income set' : 'No budget set'),
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onEditBudget,
            tooltip: isIncome ? 'Set Expected Income' : 'Set Budget',
          ),
          onLongPress: onEditCategory,
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
        onLongPress: onEditCategory, // Quick edit on long press
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color?.withOpacity(0.5) ?? Colors.grey.withOpacity(0.5),
                    radius: 16,
                    child: buildIcon(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      categoryName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: onEditBudget,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    tooltip: isIncome ? 'Edit Expected Income' : 'Edit Budget',
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
              Row(
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
                  if (isIncome)
                    Text(
                       (isOverBudget || progress >= 1)
                       ? 'Target reached!'
                       : '${CurrencyFormatter.format(budgetAmount - spentAmount, decimalDigits: 2)} to go',
                       style: TextStyle(
                         fontSize: 12,
                         color: statusColor,
                         fontWeight: FontWeight.w500,
                       ),
                    )
                  else
                    Text(
                      isOverBudget 
                          ? 'Over budget by ${CurrencyFormatter.format(spentAmount - budgetAmount, decimalDigits: 2)}'
                          : '${CurrencyFormatter.format(budgetAmount - spentAmount, decimalDigits: 2)} remaining',
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
