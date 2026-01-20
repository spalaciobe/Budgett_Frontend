import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';

class FinanceRepository {
  final SupabaseClient _client;

  FinanceRepository(this._client);

  Future<List<Account>> getAccounts() async {
    int attempts = 0;
    while (true) {
      try {
        final List<dynamic> data = await _client.from('accounts').select().order('name');
        return data.map((json) => Account.fromJson(json)).toList();
      } on PostgrestException catch (e) {
        if (attempts < 1 && (e.message.contains('JWT issued at future') || e.code == 'PGRST303')) {
          attempts++;
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        throw Exception('Error fetching accounts: $e');
      } catch (e) {
        throw Exception('Error fetching accounts: $e');
      }
    }
  }

  Future<List<Transaction>> getRecentTransactions() async {
    int attempts = 0;
    while (true) {
      try {
        final List<dynamic> data = await _client
            .from('transactions')
            .select()
            .order('date', ascending: false)
            .limit(10);
        return data.map((json) => Transaction.fromJson(json)).toList();
      } on PostgrestException catch (e) {
        if (attempts < 1 && (e.message.contains('JWT issued at future') || e.code == 'PGRST303')) {
          attempts++;
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        throw Exception('Error fetching transactions: $e');
      } catch (e) {
        throw Exception('Error fetching transactions: $e');
      }
    }
  }

  Future<void> createAccount(Map<String, dynamic> accountData) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('accounts').insert({
      ...accountData,
      'user_id': userId,
    });
  }

  // Categories
  Future<List<Category>> getCategories() async {
    final List<dynamic> data = await _client.from('categories').select().order('name');
    return data.map((json) => Category.fromJson(json)).toList();
  }

  Future<void> addCategory(Category category) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('categories').insert({
      'name': category.name,
      'type': category.type,
      'icon': category.icon,
      'color': category.color,
      'user_id': userId,
    });
  }

  // Budgets
  Future<List<Budget>> getBudgets(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final List<dynamic> data = await _client
        .from('budgets')
        .select()
        .eq('user_id', userId)
        .eq('month', month)
        .eq('year', year);
    return data.map((json) => Budget.fromJson(json)).toList();
  }

  Future<void> setBudget(Budget budget) async {
     final userId = _client.auth.currentUser!.id;
     await _client.from('budgets').upsert({
       'category_id': budget.categoryId,
       'amount': budget.amount,
       'month': budget.month,
       'year': budget.year,
       'user_id': userId,
     }, onConflict: 'category_id, month, year, user_id');
  }

  // Goals
  Future<List<Goal>> getGoals() async {
    final userId = _client.auth.currentUser!.id;
    final List<dynamic> data = await _client.from('goals').select().eq('user_id', userId);
    return data.map((json) => Goal.fromJson(json)).toList();
  }

  Future<void> addGoal(Goal goal) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('goals').insert({
      'name': goal.name,
      'target_amount': goal.targetAmount,
      'current_amount': goal.currentAmount,
      'deadline': goal.deadline?.toIso8601String(),
      'icon_name': goal.iconName,
      'user_id': userId,
    });
  }

  // Transactions (Extended)
  Future<void> addTransaction(Map<String, dynamic> transactionData) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('transactions').insert({
      ...transactionData,
      'user_id': userId,
    });
  }

  // Expense Groups
  Future<List<ExpenseGroup>> getExpenseGroups(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final List<dynamic> data = await _client
        .from('expense_groups')
        .select()
        .eq('user_id', userId)
        .eq('month', month)
        .eq('year', year)
        .order('name');
    return data.map((json) => ExpenseGroup.fromJson(json)).toList();
  }

  Future<void> createExpenseGroup(ExpenseGroup group) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('expense_groups').insert({
      'name': group.name,
      'month': group.month,
      'year': group.year,
      'budget_amount': group.budgetAmount,
      'icon': group.icon,
      'user_id': userId,
    });
  }

  Future<List<Transaction>> getTransactionsByGroup(String groupId) async {
    final List<dynamic> data = await _client
        .from('transactions')
        .select()
        .eq('expense_group_id', groupId)
        .order('date', ascending: false);
    return data.map((json) => Transaction.fromJson(json)).toList();
  }

  // Monthly Aggregations
  Future<double> getMonthlyIncome(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final result = await _client
        .from('transactions')
        .select('amount')
        .eq('user_id', userId)
        .eq('type', 'income')
        .gte('date', '$year-${month.toString().padLeft(2, '0')}-01')
        .lt('date', month == 12 
            ? '${year + 1}-01-01' 
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01');
    
    if (result.isEmpty) return 0.0;
    return result.fold<double>(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
  }

  Future<Map<String, double>> getSpendingByCategory(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final result = await _client
        .from('transactions')
        .select('category_id, amount')
        .eq('user_id', userId)
        .eq('type', 'expense')
        .gte('date', '$year-${month.toString().padLeft(2, '0')}-01')
        .lt('date', month == 12 
            ? '${year + 1}-01-01' 
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01');
    
    final Map<String, double> spending = {};
    for (var item in result) {
      final categoryId = item['category_id'] as String?;
      if (categoryId != null) {
        spending.update(
          categoryId, 
          (value) => value + (item['amount'] as num).toDouble(),
          ifAbsent: () => (item['amount'] as num).toDouble(),
        );
      }
    }
    return spending;
  }

  Future<Map<String, double>> getIncomeByCategory(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final result = await _client
        .from('transactions')
        .select('category_id, amount')
        .eq('user_id', userId)
        .eq('type', 'income')
        .gte('date', '$year-${month.toString().padLeft(2, '0')}-01')
        .lt('date', month == 12 
            ? '${year + 1}-01-01' 
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01');
    
    final Map<String, double> income = {};
    for (var item in result) {
      final categoryId = item['category_id'] as String?;
      if (categoryId != null) {
        income.update(
          categoryId, 
          (value) => value + (item['amount'] as num).toDouble(),
          ifAbsent: () => (item['amount'] as num).toDouble(),
        );
      }
    }
    return income;
  }

  Future<double> getTotalBudgeted(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final result = await _client
        .from('budgets')
        .select('amount')
        .eq('user_id', userId)
        .eq('month', month)
        .eq('year', year);
    
    if (result.isEmpty) return 0.0;
    return result.fold<double>(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
  }

  // Update and Delete Methods

  // Categories
  Future<void> updateCategory(String id, Map<String, dynamic> data) async {
    await _client.from('categories').update(data).eq('id', id);
  }

  Future<void> deleteCategory(String id) async {
    await _client.from('categories').delete().eq('id', id);
  }

  // Accounts
  Future<void> updateAccount(String id, Map<String, dynamic> data) async {
    await _client.from('accounts').update(data).eq('id', id);
  }

  Future<void> deleteAccount(String id) async {
    await _client.from('accounts').delete().eq('id', id);
  }

  // Goals
  Future<void> updateGoal(String id, Map<String, dynamic> data) async {
    await _client.from('goals').update(data).eq('id', id);
  }

  Future<void> deleteGoal(String id) async {
    await _client.from('goals').delete().eq('id', id);
  }

  // Transactions
  Future<void> updateTransaction(String id, Map<String, dynamic> data) async {
    await _client.from('transactions').update(data).eq('id', id);
  }

  Future<void> deleteTransaction(String id) async {
    await _client.from('transactions').delete().eq('id', id);
  }
}
