import '../models/transaction_model.dart';

/// Pure utility functions for balance and transaction calculations.
/// These are intentionally isolated from Supabase so they can be unit-tested
/// without network access.
class BalanceCalculator {
  /// Calculates the net balance (income − expenses) for a list of transactions.
  /// Transfers are ignored.
  static double netBalance(List<Transaction> transactions) {
    double income = 0;
    double expense = 0;
    for (final t in transactions) {
      if (t.type == 'income') {
        income += t.amount;
      } else if (t.type == 'expense') {
        expense += t.amount;
      }
    }
    return income - expense;
  }

  /// Sums all income transactions.
  static double totalIncome(List<Transaction> transactions) {
    return transactions
        .where((t) => t.type == 'income')
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Sums all expense transactions.
  static double totalExpenses(List<Transaction> transactions) {
    return transactions
        .where((t) => t.type == 'expense')
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Filters transactions by date range [from, to] inclusive.
  static List<Transaction> filterByDateRange(
    List<Transaction> transactions,
    DateTime from,
    DateTime to,
  ) {
    return transactions.where((t) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final f = DateTime(from.year, from.month, from.day);
      final e = DateTime(to.year, to.month, to.day);
      return (d.isAtSameMomentAs(f) || d.isAfter(f)) &&
          (d.isAtSameMomentAs(e) || d.isBefore(e));
    }).toList();
  }

  /// Filters transactions by a given month and year.
  static List<Transaction> filterByMonth(
    List<Transaction> transactions,
    int month,
    int year,
  ) {
    return transactions
        .where((t) => t.date.month == month && t.date.year == year)
        .toList();
  }

  /// Filters transactions by a single category ID.
  static List<Transaction> filterByCategory(
    List<Transaction> transactions,
    String categoryId,
  ) {
    return transactions.where((t) => t.categoryId == categoryId).toList();
  }

  /// Filters transactions by a single account ID.
  static List<Transaction> filterByAccount(
    List<Transaction> transactions,
    String accountId,
  ) {
    return transactions.where((t) => t.accountId == accountId).toList();
  }

  /// Groups transactions by category and returns a map of categoryId → total.
  /// Only expenses are counted by default; pass [type] to change this.
  static Map<String, double> spendingByCategory(
    List<Transaction> transactions, {
    String type = 'expense',
  }) {
    final Map<String, double> result = {};
    for (final t in transactions) {
      if (t.type != type) continue;
      if (t.categoryId == null) continue;
      result.update(
        t.categoryId!,
        (prev) => prev + t.amount,
        ifAbsent: () => t.amount,
      );
    }
    return result;
  }

  /// Returns the savings rate as a fraction [0, 1].
  /// Returns 0 if income is 0 to avoid division by zero.
  static double savingsRate(List<Transaction> transactions) {
    final income = totalIncome(transactions);
    if (income == 0) return 0;
    final expenses = totalExpenses(transactions);
    final savings = income - expenses;
    return savings / income;
  }

  /// Builds a monthly summary for a given year from a flat list of transactions.
  /// Returns a list of 12 maps with keys: month, income, expense.
  static List<Map<String, dynamic>> yearlySummary(
    List<Transaction> transactions,
    int year,
  ) {
    final monthlyStats = {
      for (int i = 1; i <= 12; i++) i: {'income': 0.0, 'expense': 0.0}
    };

    for (final t in transactions) {
      if (t.date.year != year) continue;
      final m = t.date.month;
      if (t.type == 'income') {
        monthlyStats[m]!['income'] = monthlyStats[m]!['income']! + t.amount;
      } else if (t.type == 'expense') {
        monthlyStats[m]!['expense'] = monthlyStats[m]!['expense']! + t.amount;
      }
    }

    return monthlyStats.entries
        .map((e) => {
              'month': e.key,
              'income': e.value['income'],
              'expense': e.value['expense'],
            })
        .toList();
  }
}
