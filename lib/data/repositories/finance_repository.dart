import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/data/models/profile_model.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/models/category_spending.dart';
import 'package:budgett_frontend/data/models/investment_holding_model.dart';

class FinanceRepository {
  final SupabaseClient _client;

  FinanceRepository(this._client);

  Future<List<Account>> getAccounts() async {
    int attempts = 0;
    while (true) {
      try {
        final List<dynamic> data = await _client
            .from('accounts')
            .select('*, credit_card_details(*), investment_details(*)')
            .eq('user_id', _client.auth.currentUser!.id)
            .order('name');
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
            .eq('user_id', _client.auth.currentUser!.id)
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
    final ccDetails = accountData['credit_card_details'] as Map<String, dynamic>?;
    final invDetails = accountData['investment_details'] as Map<String, dynamic>?;
    final accountRow = Map<String, dynamic>.from(accountData)
      ..remove('credit_card_details')
      ..remove('investment_details');

    final inserted = await _client
        .from('accounts')
        .insert({...accountRow, 'user_id': userId})
        .select('id')
        .single();

    if (ccDetails != null) {
      await _client.from('credit_card_details').upsert(
        {...ccDetails, 'account_id': inserted['id']},
        onConflict: 'account_id',
      );
    }

    if (invDetails != null) {
      await _client.from('investment_details').upsert(
        {...invDetails, 'account_id': inserted['id']},
        onConflict: 'account_id',
      );
    }
  }

  // Categories
  Future<List<Category>> getCategories() async {
    final List<dynamic> data = await _client.from('categories').select('*, sub_categories(*)').eq('user_id', _client.auth.currentUser!.id).order('name');
    return data.map((json) => Category.fromJson(json)).toList();
  }

  Future<Category> addCategoryWithReturn(Category category) async {
    final userId = _client.auth.currentUser!.id;
    final List<dynamic> data = await _client.from('categories').insert({
      'name': category.name,
      'type': category.type,
      'icon': category.icon,
      'color': category.color,
      'user_id': userId,
    }).select();
    
    return Category.fromJson(data.first);
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

  // ── Billing Calendar (manual overrides) ─────────────────────────────────

  /// Returns overrides for a given account/year, keyed by month (1-12).
  Future<Map<int, ({DateTime cutoff, DateTime payment})>> getBillingCalendar(
      String accountId, int year) async {
    final data = await _client
        .from('bank_billing_calendar')
        .select('month, fecha_corte, fecha_pago')
        .eq('account_id', accountId)
        .eq('year', year);

    return {
      for (final row in data)
        (row['month'] as int): (
          cutoff: DateTime.parse(row['fecha_corte'] as String),
          payment: DateTime.parse(row['fecha_pago'] as String),
        ),
    };
  }

  Future<void> upsertBillingCalendarEntry(
      String accountId, int year, int month, DateTime cutoff, DateTime payment) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('bank_billing_calendar').upsert({
      'account_id': accountId,
      'user_id': userId,
      'year': year,
      'month': month,
      'fecha_corte': cutoff.toIso8601String().split('T')[0],
      'fecha_pago': payment.toIso8601String().split('T')[0],
    }, onConflict: 'account_id, year, month');
  }

  Future<void> deleteBillingCalendarEntry(
      String accountId, int year, int month) async {
    await _client
        .from('bank_billing_calendar')
        .delete()
        .eq('account_id', accountId)
        .eq('year', year)
        .eq('month', month);
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

  /// Copia los presupuestos del mes anterior al mes/año indicado.
  /// Si ya existen presupuestos para ese mes, los sobreescribe (upsert).
  /// Retorna el número de presupuestos copiados.
  Future<int> copyBudgetsFromPreviousMonth(int month, int year) async {
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear = month == 1 ? year - 1 : year;

    final previous = await getBudgets(prevMonth, prevYear);
    if (previous.isEmpty) return 0;

    for (final budget in previous) {
      await setBudget(Budget(
        id: '',
        categoryId: budget.categoryId,
        amount: budget.amount,
        month: month,
        year: year,
      ));
    }
    return previous.length;
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

  Future<void> addSubCategory(SubCategory subCategory) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('sub_categories').insert({
      'name': subCategory.name,
      'category_id': subCategory.categoryId,
      'user_id': userId,
    });
  }

  Future<void> deleteSubCategory(String id) async {
    await _client.from('sub_categories').delete().eq('id', id);
  }

  // Expense Groups
  Future<List<ExpenseGroup>> getExpenseGroups() async {
    final userId = _client.auth.currentUser!.id;
    final List<dynamic> data = await _client
        .from('expense_groups')
        .select()
        .eq('user_id', userId)
        .order('start_date', ascending: false);
    return data.map((json) => ExpenseGroup.fromJson(json)).toList();
  }

  Future<void> createExpenseGroup(ExpenseGroup group) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('expense_groups').insert({
      'name': group.name,
      'start_date': group.startDate.toIso8601String().split('T')[0],
      'end_date': group.endDate?.toIso8601String().split('T')[0],
      'budget_amount': group.budgetAmount,
      'icon': group.icon,
      'user_id': userId,
    });
  }
  
  Future<void> updateExpenseGroup(String id, Map<String, dynamic> data) async {
    await _client.from('expense_groups').update(data).eq('id', id);
  }

  Future<void> deleteExpenseGroup(String id) async {
    await _client.from('expense_groups').delete().eq('id', id);
  }

  Future<List<Transaction>> getTransactionsByGroup(String groupId) async {
    final List<dynamic> data = await _client
        .from('transactions')
        .select()
        .eq('expense_group_id', groupId)
        .order('date', ascending: false);
    return data.map((json) => Transaction.fromJson(json)).toList();
  }

  Future<List<Transaction>> getTransactionsForAccount(String accountId, {int limit = 50}) async {
    final List<dynamic> data = await _client
        .from('transactions')
        .select()
        .eq('account_id', accountId)
        .order('date', ascending: false)
        .limit(limit);
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
        .eq('currency', 'COP') // Budgets are COP-only
        .gte('date', '$year-${month.toString().padLeft(2, '0')}-01')
        .lt('date', month == 12
            ? '${year + 1}-01-01'
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01');

    if (result.isEmpty) return 0.0;
    return result.fold<double>(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
  }

  Future<Map<String, CategorySpending>> getSpendingByCategory(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final result = await _client
        .from('transactions')
        .select('category_id, sub_category_id, amount')
        .eq('user_id', userId)
        .eq('type', 'expense')
        .eq('currency', 'COP') // Budgets are COP-only
        .gte('date', '$year-${month.toString().padLeft(2, '0')}-01')
        .lt('date', month == 12
            ? '${year + 1}-01-01'
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01');
    
    final Map<String, CategorySpending> spending = {};
    for (var item in result) {
      final categoryId = item['category_id'] as String?;
      final subCategoryId = item['sub_category_id'] as String?;
      final amount = (item['amount'] as num).toDouble();
      
      if (categoryId != null) {
        spending.putIfAbsent(categoryId, () => CategorySpending());
        spending[categoryId]!.total += amount;
        
        if (subCategoryId != null) {
          spending[categoryId]!.subCategories.update(
            subCategoryId, 
            (val) => val + amount, 
            ifAbsent: () => amount
          );
        }
      }
    }
    return spending;
  }

  Future<Map<String, CategorySpending>> getIncomeByCategory(int month, int year) async {
    final userId = _client.auth.currentUser!.id;
    final result = await _client
        .from('transactions')
        .select('category_id, sub_category_id, amount')
        .eq('user_id', userId)
        .eq('type', 'income')
        .eq('currency', 'COP') // Budgets are COP-only
        .gte('date', '$year-${month.toString().padLeft(2, '0')}-01')
        .lt('date', month == 12
            ? '${year + 1}-01-01'
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01');
    
    final Map<String, CategorySpending> income = {};
    for (var item in result) {
      final categoryId = item['category_id'] as String?;
      final subCategoryId = item['sub_category_id'] as String?;
      final amount = (item['amount'] as num).toDouble();
      
      if (categoryId != null) {
        income.putIfAbsent(categoryId, () => CategorySpending());
        income[categoryId]!.total += amount;
        
        if (subCategoryId != null) {
          income[categoryId]!.subCategories.update(
            subCategoryId, 
            (val) => val + amount, 
            ifAbsent: () => amount
          );
        }
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
    final ccDetails = data['credit_card_details'] as Map<String, dynamic>?;
    final invDetails = data['investment_details'] as Map<String, dynamic>?;
    final accountRow = Map<String, dynamic>.from(data)
      ..remove('credit_card_details')
      ..remove('investment_details');

    if (accountRow.isNotEmpty) {
      await _client.from('accounts').update(accountRow).eq('id', id);
    }

    if (ccDetails != null) {
      await _client.from('credit_card_details').upsert(
        {...ccDetails, 'account_id': id},
        onConflict: 'account_id',
      );
    }

    if (invDetails != null) {
      await _client.from('investment_details').upsert(
        {...invDetails, 'account_id': id},
        onConflict: 'account_id',
      );
    }
  }

  Future<void> deleteAccount(String id) async {
    await _client.from('accounts').delete().eq('id', id);
  }

  // ── Investment Holdings ──────────────────────────────────────────────────

  Future<List<InvestmentHolding>> getHoldings(String accountId) async {
    int attempts = 0;
    while (true) {
      try {
        final List<dynamic> data = await _client
            .from('investment_holdings')
            .select()
            .eq('account_id', accountId)
            .order('symbol');
        return data.map((json) => InvestmentHolding.fromJson(json)).toList();
      } on PostgrestException catch (e) {
        if (attempts < 1 && (e.message.contains('JWT issued at future') || e.code == 'PGRST303')) {
          attempts++;
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        throw Exception('Error fetching holdings: $e');
      } catch (e) {
        throw Exception('Error fetching holdings: $e');
      }
    }
  }

  Future<InvestmentHolding> createHolding(Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('investment_holdings')
        .insert({...data, 'user_id': userId})
        .select()
        .single();
    return InvestmentHolding.fromJson(row);
  }

  Future<void> updateHolding(String id, Map<String, dynamic> data) async {
    await _client
        .from('investment_holdings')
        .update({...data, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  Future<void> deleteHolding(String id) async {
    await _client.from('investment_holdings').delete().eq('id', id);
  }

  /// Batch-update current_price for multiple holdings.
  Future<void> updateHoldingsPrices(
      List<({String id, double price})> updates) async {
    for (final u in updates) {
      await _client.from('investment_holdings').update({
        'current_price': u.price,
        'price_updated_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', u.id);
    }
  }

  /// Records a buy: creates an expense transaction and updates the holding's
  /// quantity and avg_cost in one repository call.
  ///
  /// [transactionData] should contain at minimum: description, date, category_id.
  Future<void> buyHolding({
    required String accountId,
    required String holdingId,
    required double quantity,
    required double pricePerUnit,
    double fee = 0.0,
    String currency = 'COP',
    Map<String, dynamic> transactionData = const {},
  }) async {
    final userId = _client.auth.currentUser!.id;
    final totalAmount = quantity * pricePerUnit + fee;

    // 1. Fetch current holding state
    final holdingRow = await _client
        .from('investment_holdings')
        .select('quantity, avg_cost')
        .eq('id', holdingId)
        .single();

    final currentQty = (holdingRow['quantity'] as num).toDouble();
    final currentAvg = (holdingRow['avg_cost'] as num).toDouble();
    final newQty = currentQty + quantity;
    final newAvg = newQty == 0
        ? 0.0
        : (currentQty * currentAvg + quantity * pricePerUnit) / newQty;

    // 2. Insert expense transaction (decreases cash in investment account)
    await _client.from('transactions').insert({
      ...transactionData,
      'user_id': userId,
      'account_id': accountId,
      'amount': totalAmount,
      'type': 'expense',
      'currency': currency,
      'holding_id': holdingId,
    });

    // 3. Update holding position
    await _client.from('investment_holdings').update({
      'quantity': newQty,
      'avg_cost': newAvg,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', holdingId);
  }

  /// Records a sell: creates an income transaction and decreases the holding's
  /// quantity.
  Future<void> sellHolding({
    required String accountId,
    required String holdingId,
    required double quantity,
    required double pricePerUnit,
    double fee = 0.0,
    String currency = 'COP',
    Map<String, dynamic> transactionData = const {},
  }) async {
    final userId = _client.auth.currentUser!.id;
    final proceeds = quantity * pricePerUnit - fee;

    // 1. Fetch current holding state
    final holdingRow = await _client
        .from('investment_holdings')
        .select('quantity, avg_cost')
        .eq('id', holdingId)
        .single();

    final currentQty = (holdingRow['quantity'] as num).toDouble();
    final newQty = (currentQty - quantity).clamp(0.0, double.infinity);

    // 2. Insert income transaction (increases cash in investment account)
    await _client.from('transactions').insert({
      ...transactionData,
      'user_id': userId,
      'account_id': accountId,
      'amount': proceeds,
      'type': 'income',
      'currency': currency,
      'holding_id': holdingId,
    });

    // 3. Update holding quantity (avg_cost stays the same on a sell)
    await _client.from('investment_holdings').update({
      'quantity': newQty,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', holdingId);
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

  // Recurring Transactions
  Future<List<RecurringTransaction>> getRecurringTransactions() async {
    final userId = _client.auth.currentUser!.id;
    final List<dynamic> data = await _client
        .from('recurring_transactions')
        .select()
        .eq('user_id', userId)
        .order('next_run_date');
    return data.map((json) => RecurringTransaction.fromJson(json)).toList();
  }

  Future<void> addRecurringTransaction(RecurringTransaction transaction) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('recurring_transactions').insert({
      ...transaction.toJson(),
      'user_id': userId,
    });
  }

  Future<void> updateRecurringTransaction(String id, Map<String, dynamic> data) async {
    await _client.from('recurring_transactions').update(data).eq('id', id);
  }

  Future<void> deleteRecurringTransaction(String id) async {
    await _client.from('recurring_transactions').delete().eq('id', id);
  }

  // Helper to generate transaction from recurring
  Future<void> generateTransactionFromRecurring(RecurringTransaction recurring) async {
    // 1. Create the real transaction
    await addTransaction({
      'description': recurring.description,
      'amount': recurring.amount,
      'category_id': recurring.categoryId,
      'account_id': recurring.accountId,
      'type': recurring.type,
      // 'movement_type': recurring.movementType, // If we added this to model
      'date': DateTime.now().toIso8601String().split('T')[0],
      'status': 'paid', // Or pending based on preference
      'notes': 'Generated from recurring: ${recurring.description}',
    });

    // 2. Update the next run date
    DateTime nextDate = recurring.nextRunDate;
    switch (recurring.frequency) {
      case 'daily':
        nextDate = nextDate.add(const Duration(days: 1));
        break;
      case 'weekly':
        nextDate = nextDate.add(const Duration(days: 7));
        break;
      case 'biweekly':
        nextDate = nextDate.add(const Duration(days: 14));
        break;
      case 'monthly':
        nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day);
        break;
      case 'yearly':
        nextDate = DateTime(nextDate.year + 1, nextDate.month, nextDate.day);
        break;
    }

    await updateRecurringTransaction(recurring.id, {
      'last_run_date': DateTime.now().toIso8601String().split('T')[0],
      'next_run_date': nextDate.toIso8601String().split('T')[0],
    });
  }

  // Dashboard / Analysis
  Future<List<Map<String, dynamic>>> getYearlySummary(int year) async {
    int attempts = 0;
    while (true) {
      try {
        final userId = _client.auth.currentUser!.id;
        final result = await _client
            .from('transactions')
            .select('date, amount, type, currency')
            .eq('user_id', userId)
            .eq('status', 'paid')
            .gte('date', '$year-01-01')
            .lte('date', '$year-12-31');

        // Group by month — separate COP and USD slices
        final Map<int, Map<String, double>> monthlyStats = {
          for (int i = 1; i <= 12; i++)
            i: {
              'income': 0.0,
              'expense': 0.0,
              'income_usd': 0.0,
              'expense_usd': 0.0,
            },
        };

        for (var item in result) {
          final date = DateTime.parse(item['date'] as String);
          final amount = (item['amount'] as num).toDouble();
          final type = item['type'] as String;
          final currency = (item['currency'] as String?) ?? 'COP';

          if (type == 'income') {
            if (currency == 'USD') {
              monthlyStats[date.month]!['income_usd'] =
                  monthlyStats[date.month]!['income_usd']! + amount;
            } else {
              monthlyStats[date.month]!['income'] =
                  monthlyStats[date.month]!['income']! + amount;
            }
          } else if (type == 'expense') {
            if (currency == 'USD') {
              monthlyStats[date.month]!['expense_usd'] =
                  monthlyStats[date.month]!['expense_usd']! + amount;
            } else {
              monthlyStats[date.month]!['expense'] =
                  monthlyStats[date.month]!['expense']! + amount;
            }
          }
          // 'transfer' type is intentionally skipped — not income or expense
        }

        final entries = monthlyStats.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        return entries
            .map((e) => {
                  'month': e.key,
                  'income': e.value['income'],
                  'expense': e.value['expense'],
                  'income_usd': e.value['income_usd'],
                  'expense_usd': e.value['expense_usd'],
                })
            .toList();
      } on PostgrestException catch (e) {
        if (attempts < 1 &&
            (e.message.contains('JWT issued at future') ||
                e.code == 'PGRST303')) {
          attempts++;
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        throw Exception('Error fetching yearly summary: $e');
      } catch (e) {
        throw Exception('Error fetching yearly summary: $e');
      }
    }
  }

  Future<ProfileModel?> getProfile() async {
    final userId = _client.auth.currentUser!.id;
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return ProfileModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw Exception('Error fetching profile: $e');
    } catch (e) {
      throw Exception('Error fetching profile: $e');
    }
  }

  Future<void> updateProfile({
    String? username,
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    final userId = _client.auth.currentUser!.id;
    try {
      await _client.from('profiles').upsert({
        'id': userId,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
      });
    } on PostgrestException catch (e) {
      throw Exception('Error updating profile: $e');
    } catch (e) {
      throw Exception('Error updating profile: $e');
    }
  }
}

