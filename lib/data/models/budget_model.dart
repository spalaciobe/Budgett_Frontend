/// A category's budget for one month.
///
/// [amount] is the *effective* budget: the larger of the explicit category
/// budget ([categoryAmount], a row in `budgets`) and the sum of its
/// sub-category budgets ([subCategoryBudgets], rows in
/// `sub_category_budgets`). By default a category's budget is the sum of its
/// sub-categories; an explicit category budget only takes over when it is
/// larger, and the difference is money not assigned to any sub-category.
class Budget {
  final String id;
  final String categoryId;

  /// Effective budgeted amount — what every screen compares spending against.
  final double amount;
  final int month;
  final int year;

  /// Explicit category-level budget, or null when there is no `budgets` row
  /// (the budget then comes entirely from the sub-categories).
  final double? categoryAmount;

  /// Sub-category id → budgeted amount for this month.
  final Map<String, double> subCategoryBudgets;

  Budget({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.month,
    required this.year,
    double? categoryAmount,
    Map<String, double>? subCategoryBudgets,
  })  : categoryAmount = categoryAmount ??
            ((subCategoryBudgets == null || subCategoryBudgets.isEmpty)
                ? amount
                : null),
        subCategoryBudgets = subCategoryBudgets ?? const {};

  /// Merges an explicit category budget with its sub-category budgets.
  factory Budget.effective({
    required String id,
    required String categoryId,
    required int month,
    required int year,
    double? categoryAmount,
    Map<String, double> subCategoryBudgets = const {},
  }) {
    return Budget(
      id: id,
      categoryId: categoryId,
      amount: effectiveAmount(categoryAmount, subCategoryBudgets),
      month: month,
      year: year,
      categoryAmount: categoryAmount,
      subCategoryBudgets: subCategoryBudgets,
    );
  }

  /// Sum of the sub-category budgets.
  double get subCategoryTotal => sumSubBudgets(subCategoryBudgets);

  /// Part of the category budget not assigned to any sub-category.
  double get unassigned =>
      (amount - subCategoryTotal).clamp(0.0, double.infinity);

  static double sumSubBudgets(Map<String, double> subs) =>
      subs.values.fold<double>(0.0, (sum, v) => sum + v);

  /// The single rule for a category's effective budget: the explicit budget
  /// wins only when it is larger than the sum of its sub-categories.
  static double effectiveAmount(
      double? categoryAmount, Map<String, double> subCategoryBudgets) {
    final subs = sumSubBudgets(subCategoryBudgets);
    final explicit = categoryAmount ?? 0.0;
    return explicit > subs ? explicit : subs;
  }

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      categoryId: json['category_id'],
      amount: (json['amount'] as num).toDouble(),
      month: json['month'],
      year: json['year'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'amount': amount,
      'month': month,
      'year': year,
    };
  }
}
