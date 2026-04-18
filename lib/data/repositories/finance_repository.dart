import 'dart:typed_data';

import 'package:image/image.dart' as img;
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
import 'package:budgett_frontend/data/models/savings_interest_details_model.dart';
import 'package:budgett_frontend/data/models/credit_card_rules_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/core/utils/credit_card_calculator.dart';
import 'package:budgett_frontend/core/utils/installment_calculator.dart';

class FinanceRepository {
  final SupabaseClient _client;

  FinanceRepository(this._client);

  /// Returns true for transient network errors (DNS failure, connection reset,
  /// etc.) that are worth retrying once on app first load.
  bool _isTransientNetworkError(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('ClientException');
  }

  /// Executes [fn] and retries once on:
  ///   - JWT clock-skew (PGRST303 / "JWT issued at future")
  ///   - Transient network errors (DNS not yet ready, connection reset, etc.)
  Future<T> _withRetry<T>(
      Future<T> Function() fn, String errorContext) async {
    int attempts = 0;
    while (true) {
      try {
        return await fn();
      } on PostgrestException catch (e) {
        if (attempts < 1 &&
            (e.message.contains('JWT issued at future') ||
                e.code == 'PGRST303')) {
          attempts++;
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        throw Exception('$errorContext: $e');
      } catch (e) {
        if (attempts < 1 && _isTransientNetworkError(e)) {
          attempts++;
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        throw Exception('$errorContext: $e');
      }
    }
  }

  Future<List<Account>> getAccounts() => _withRetry(() async {
        final List<dynamic> data = await _client
            .from('accounts')
            .select(
              '*, credit_card_details(*), investment_details(*), '
              'savings_interest_details(*), '
              'pockets:accounts!parent_account_id(*, savings_interest_details(*))',
            )
            .eq('user_id', _client.auth.currentUser!.id)
            .isFilter('parent_account_id', null)
            .order('name');
        return data.map((json) => Account.fromJson(json)).toList();
      }, 'Error fetching accounts');

  Future<List<Transaction>> getRecentTransactions() => _withRetry(() async {
        final List<dynamic> data = await _client
            .from('transactions')
            .select()
            .eq('user_id', _client.auth.currentUser!.id)
            .eq('is_installment_parent', false)
            .order('date', ascending: false)
            .order('created_at', ascending: false);
        return data.map((json) => Transaction.fromJson(json)).toList();
      }, 'Error fetching transactions');

  Future<String> createAccount(Map<String, dynamic> accountData) async {
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

    final accountId = inserted['id'] as String;

    if (ccDetails != null) {
      await _client.from('credit_card_details').upsert(
        {...ccDetails, 'account_id': accountId},
        onConflict: 'account_id',
      );
    }

    if (invDetails != null) {
      await _client.from('investment_details').upsert(
        {...invDetails, 'account_id': accountId},
        onConflict: 'account_id',
      );
    }

    return accountId;
  }

  /// Resizes [bytes] to 256×256, uploads to the account-icons bucket, and
  /// returns the public URL. Overwrites any previous icon for this account.
  Future<String> uploadAccountIcon(String accountId, Uint8List bytes) async {
    final userId = _client.auth.currentUser!.id;

    // Decode → center-crop to square → resize to 256×256 → encode as JPEG.
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');
    final cropped = img.copyResizeCropSquare(decoded, size: 256);
    final compressed = Uint8List.fromList(img.encodeJpg(cropped, quality: 85));

    final path = '$userId/$accountId.jpg';
    await _client.storage.from('account-icons').uploadBinary(
      path,
      compressed,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );

    return _client.storage.from('account-icons').getPublicUrl(path);
  }

  // Categories
  Future<List<Category>> getCategories() => _withRetry(() async {
        final List<dynamic> data = await _client
            .from('categories')
            .select('*, sub_categories(*)')
            .eq('user_id', _client.auth.currentUser!.id)
            .order('name');
        return data.map((json) => Category.fromJson(json)).toList();
      }, 'Error fetching categories');

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
  Future<List<Budget>> getBudgets(int month, int year) => _withRetry(() async {
        final userId = _client.auth.currentUser!.id;
        final List<dynamic> data = await _client
            .from('budgets')
            .select()
            .eq('user_id', userId)
            .eq('month', month)
            .eq('year', year);
        return data.map((json) => Budget.fromJson(json)).toList();
      }, 'Error fetching budgets');

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
  Future<List<Goal>> getGoals() => _withRetry(() async {
        final userId = _client.auth.currentUser!.id;
        final List<dynamic> data =
            await _client.from('goals').select().eq('user_id', userId);
        return data.map((json) => Goal.fromJson(json)).toList();
      }, 'Error fetching goals');

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

  /// Posts a credit-card payment: transfers [debitAmount] in [sourceCurrency]
  /// from [sourceAccountId] and credits [settleAmount] in [debtCurrency] to
  /// [cardAccountId]. If the two currencies differ, fx_rate is derived as
  /// debitAmount / settleAmount (what the bank actually charged / what was
  /// settled on the card), so the stored rate matches reality rather than a
  /// guessed market rate.
  ///
  /// When [closedInstallmentIds] is non-empty, those pending installment
  /// children are flipped to status='paid' with date=today BEFORE the payment
  /// transaction is inserted, so their balance effect is already posted when
  /// the transfer arrives. Caller must have included their amounts inside
  /// [settleAmount] so the card balance nets to the intended value.
  Future<void> payCreditCard({
    required String sourceAccountId,
    required String cardAccountId,
    required double settleAmount,
    required String debtCurrency,
    required double debitAmount,
    required String sourceCurrency,
    required DateTime date,
    String? notes,
    List<String> closedInstallmentIds = const [],
  }) async {
    final userId = _client.auth.currentUser!.id;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    if (closedInstallmentIds.isNotEmpty) {
      await _client
          .from('transactions')
          .update({'status': 'paid', 'date': dateStr})
          .inFilter('id', closedInstallmentIds)
          .eq('user_id', userId);
    }

    final crossCurrency = debtCurrency != sourceCurrency;
    final payload = <String, dynamic>{
      'account_id': sourceAccountId,
      'target_account_id': cardAccountId,
      'amount': debitAmount,
      'currency': sourceCurrency,
      'type': 'transfer',
      'status': 'paid',
      'date': dateStr,
      'description': 'Credit card payment',
      'is_credit_card_payment': true,
      'closed_installment_ids': closedInstallmentIds,
      'user_id': userId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (crossCurrency) 'target_currency': debtCurrency,
      if (crossCurrency) 'fx_rate': debitAmount / settleAmount,
    };

    await _client.from('transactions').insert(payload);
  }

  /// Records savings-account interest as an [income] transaction and advances
  /// [savings_interest_details.last_interest_date] to [date].
  ///
  /// Call this whenever the user formalises accrued interest on a savings
  /// account (parent or pocket). The next accrual calculation will start from
  /// [date] going forward. To change the APY cleanly, call [updateSavingsApy]
  /// instead — that closes a segment with the old rate before applying the new.
  Future<void> recordSavingsInterest({
    required String accountId,
    required String detailsId,
    required double amount,
    required DateTime date,
    required String currency,
    required String accountName,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    await addTransaction({
      'account_id': accountId,
      'amount': amount,
      'type': 'income',
      'currency': currency,
      'description': 'Interest — $accountName',
      'date': dateStr,
      'movement_type': 'income',
      'status': 'paid',
    });

    await _client
        .from('savings_interest_details')
        .update({
          'last_interest_date': dateStr,
          'period_segments': <dynamic>[],
        })
        .eq('id', detailsId);
  }

  /// Closes the current balance/rate sub-period for a savings account that
  /// earns interest. Call this **before** the balance or APY changes so the
  /// closed segment records the balance/rate that were in effect up to [segmentEnd].
  ///
  /// Silently no-ops when [segmentEnd] is not after the computed start date
  /// (e.g. backdated transactions earlier than [lastInterestDate]).
  Future<void> appendSavingsInterestSegment({
    required String detailsId,
    required DateTime segmentEnd,
    required double balance,
    required double apyRate,
    required DateTime lastInterestDate,
  }) async {
    final data = await _client
        .from('savings_interest_details')
        .select('period_segments')
        .eq('id', detailsId)
        .single();

    final List<dynamic> existing =
        (data['period_segments'] as List<dynamic>?) ?? [];

    DateTime segmentStart;
    if (existing.isNotEmpty) {
      final lastEntry = existing.last as Map<String, dynamic>;
      segmentStart = DateTime.parse(lastEntry['to'] as String);
    } else {
      segmentStart = lastInterestDate;
    }

    final startNorm =
        DateTime(segmentStart.year, segmentStart.month, segmentStart.day);
    final endNorm =
        DateTime(segmentEnd.year, segmentEnd.month, segmentEnd.day);

    if (!endNorm.isAfter(startNorm)) return;

    final newSegment = InterestPeriodSegment(
      from: startNorm,
      to: endNorm,
      balance: balance,
      apyRate: apyRate,
    );

    existing.add(newSegment.toJson());

    await _client
        .from('savings_interest_details')
        .update({'period_segments': existing})
        .eq('id', detailsId);
  }

  /// Creates a pocket (child savings account) under [parentAccountId].
  /// Optionally attaches APY configuration via savings_interest_details.
  Future<String> createPocket({
    required String parentAccountId,
    required String name,
    String? icon,
    double? apyRate,
    String? interestPeriod,
    DateTime? lastInterestDate,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final inserted = await _client
        .from('accounts')
        .insert({
          'user_id': userId,
          'name': name,
          'type': 'savings',
          'balance': 0,
          'balance_usd': 0,
          'icon': icon,
          'parent_account_id': parentAccountId,
          'is_active': true,
        })
        .select('id')
        .single();

    final pocketId = inserted['id'] as String;

    if (apyRate != null || interestPeriod != null) {
      await _client.from('savings_interest_details').insert({
        'account_id': pocketId,
        'apy_rate': apyRate,
        'interest_period': interestPeriod,
        'last_interest_date': lastInterestDate != null
            ? '${lastInterestDate.year}-${lastInterestDate.month.toString().padLeft(2, '0')}-${lastInterestDate.day.toString().padLeft(2, '0')}'
            : null,
      });
    }

    return pocketId;
  }

  /// Creates a savings_interest_details row for an existing savings account
  /// (parent or pocket) that did not have one yet.
  Future<String> createSavingsInterestDetails({
    required String accountId,
    double? apyRate,
    String? interestPeriod,
    DateTime? lastInterestDate,
  }) async {
    final inserted = await _client
        .from('savings_interest_details')
        .insert({
          'account_id': accountId,
          'apy_rate': apyRate,
          'interest_period': interestPeriod,
          'last_interest_date': lastInterestDate != null
              ? '${lastInterestDate.year}-${lastInterestDate.month.toString().padLeft(2, '0')}-${lastInterestDate.day.toString().padLeft(2, '0')}'
              : null,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Changes the APY of a savings account safely: closes the current segment
  /// with the OLD rate first so accrued-interest math remains correct.
  Future<void> updateSavingsApy({
    required String detailsId,
    required double? oldApyRate,
    required double oldBalance,
    required DateTime? lastInterestDate,
    required double newApyRate,
    String? newInterestPeriod,
  }) async {
    if (oldApyRate != null &&
        oldApyRate > 0 &&
        oldBalance > 0 &&
        lastInterestDate != null) {
      await appendSavingsInterestSegment(
        detailsId: detailsId,
        segmentEnd: DateTime.now(),
        balance: oldBalance,
        apyRate: oldApyRate,
        lastInterestDate: lastInterestDate,
      );
    }

    final patch = <String, dynamic>{'apy_rate': newApyRate};
    if (newInterestPeriod != null) {
      patch['interest_period'] = newInterestPeriod;
    }
    await _client
        .from('savings_interest_details')
        .update(patch)
        .eq('id', detailsId);
  }

  /// Deletes a pocket and everything that cascades from it (transactions,
  /// savings_interest_details). Caller is responsible for confirming with the
  /// user first — this is destructive.
  Future<void> deletePocket(String pocketId) async {
    await _client.from('accounts').delete().eq('id', pocketId);
  }

  Future<void> rawUpdateInvestmentDetails(
      String id, Map<String, dynamic> data) async {
    await _client.from('investment_details').update(data).eq('id', id);
  }

  Future<void> rawUpdateSavingsInterestDetails(
      String id, Map<String, dynamic> data) async {
    await _client.from('savings_interest_details').update(data).eq('id', id);
  }

  Future<void> addSubCategory(SubCategory subCategory) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('sub_categories').insert({
      'name': subCategory.name,
      'category_id': subCategory.categoryId,
      'user_id': userId,
    });
  }

  Future<void> updateSubCategory(String id, Map<String, dynamic> data) async {
    await _client.from('sub_categories').update(data).eq('id', id);
  }

  Future<void> deleteSubCategory(String id) async {
    await _client.from('sub_categories').delete().eq('id', id);
  }

  // Expense Groups
  Future<List<ExpenseGroup>> getExpenseGroups() => _withRetry(() async {
        final userId = _client.auth.currentUser!.id;
        final List<dynamic> data = await _client
            .from('expense_groups')
            .select()
            .eq('user_id', userId)
            .order('start_date', ascending: false);
        return data.map((json) => ExpenseGroup.fromJson(json)).toList();
      }, 'Error fetching expense groups');

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
    return getTransactionsForAccounts([accountId], limit: limit);
  }

  /// Fetch transactions where any of [accountIds] appears as the source
  /// (`account_id`) or the destination (`target_account_id`) of a transfer.
  /// Used for savings parents that want to include pocket transactions.
  Future<List<Transaction>> getTransactionsForAccounts(
    List<String> accountIds, {
    int limit = 50,
  }) async {
    if (accountIds.isEmpty) return [];
    final csv = accountIds.join(',');
    final List<dynamic> data = await _client
        .from('transactions')
        .select()
        .or('account_id.in.($csv),target_account_id.in.($csv)')
        .eq('is_installment_parent', false)
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
        .eq('is_installment_parent', false) // exclude display-only parent rows
        .neq('status', 'pending') // pending transactions don't count as spent
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

  Future<List<InvestmentHolding>> getHoldings(String accountId) =>
      _withRetry(() async {
        final List<dynamic> data = await _client
            .from('investment_holdings')
            .select()
            .eq('account_id', accountId)
            .order('symbol');
        return data.map((json) => InvestmentHolding.fromJson(json)).toList();
      }, 'Error fetching holdings');

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

  /// Invokes the `update-prices` Edge Function which fetches live prices for
  /// all holdings in [accountId] from CoinGecko (crypto) and Yahoo Finance
  /// (stocks/ETFs) and writes them to `investment_holdings`.
  ///
  /// Returns `(updatedCount, skipped)` where `skipped` is a list of
  /// `(symbol, reason)` for holdings that could not be priced.
  Future<({int updatedCount, List<({String symbol, String reason})> skipped})>
      fetchMarketPrices(String accountId) async {
    final res = await _client.functions.invoke(
      'update-prices',
      body: {'accountId': accountId},
    );
    final data = res.data;
    if (data is! Map) {
      throw Exception('Unexpected response from update-prices: $data');
    }
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    final updated = (data['updated'] as List? ?? const []);
    final skippedRaw = (data['skipped'] as List? ?? const []);
    final skipped = skippedRaw
        .whereType<Map>()
        .map((m) => (
              symbol: (m['symbol'] ?? '').toString(),
              reason: (m['reason'] ?? '').toString(),
            ))
        .toList();
    return (updatedCount: updated.length, skipped: skipped);
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

  /// Creates an installment purchase: one parent row + N child rows.
  ///
  /// The parent carries [is_installment_parent = true] and stores the full
  /// [amount] for display. It does NOT affect the account balance (the trigger
  /// skips parent rows). Each child row holds the monthly payment and lands in
  /// its own billing period, hitting the balance normally via the trigger.
  ///
  /// Returns the parent transaction id.
  Future<String> createInstallmentPurchase({
    required String accountId,
    required double amount,
    required int numCuotas,
    required bool hasInterest,
    required double interestRate,
    required DateTime purchaseDate,
    required String currency,
    required String description,
    required CreditCardRules rules,
    required Bank bank,
    String? categoryId,
    String? subCategoryId,
    String? expenseGroupId,
    String? notes,
    String? place,
    String? movementType,
    String status = 'paid',
  }) async {
    final userId = _client.auth.currentUser!.id;
    final dateStr =
        '${purchaseDate.year}-${purchaseDate.month.toString().padLeft(2, '0')}-${purchaseDate.day.toString().padLeft(2, '0')}';

    // Billing info for the parent row (purchase date's own cycle).
    final parentBillingPeriod =
        CreditCardCalculator.determineBillingPeriod(purchaseDate, rules, bank);
    final parts = parentBillingPeriod.split('-');
    final parentCutoff = CreditCardCalculator.calculateCutoffDate(
        rules, bank, int.parse(parts[0]), int.parse(parts[1]));
    final parentPayment =
        CreditCardCalculator.calculatePaymentDate(rules, bank, parentCutoff);

    // 1. Insert the parent row.
    final parentRow = await _client.from('transactions').insert({
      'user_id': userId,
      'account_id': accountId,
      'amount': amount,
      'original_purchase_amount': amount,
      'description': description,
      'date': dateStr,
      'type': 'expense',
      'status': status,
      'currency': currency,
      'is_installment_parent': true,
      'num_cuotas': numCuotas,
      'has_interest': hasInterest,
      'interest_rate': hasInterest ? interestRate : null,
      if (categoryId != null) 'category_id': categoryId,
      if (subCategoryId != null) 'sub_category_id': subCategoryId,
      if (expenseGroupId != null) 'expense_group_id': expenseGroupId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (place != null && place.isNotEmpty) 'place': place,
      if (movementType != null) 'movement_type': movementType,
      'periodo_facturacion': parentBillingPeriod,
      'fecha_corte_calculada':
          parentCutoff.toIso8601String().split('T')[0],
      'fecha_pago_calculada':
          parentPayment.toIso8601String().split('T')[0],
    }).select('id').single();

    final parentId = parentRow['id'] as String;

    // 2. Generate schedule and batch-insert children.
    try {
      final schedule = InstallmentCalculator.generateSchedule(
        purchaseDate: purchaseDate,
        rules: rules,
        bank: bank,
        numCuotas: numCuotas,
        hasInterest: hasInterest,
        monthlyRate: interestRate,
        principal: amount,
      );

      final childRows = schedule
          .map((e) => {
                'user_id': userId,
                'account_id': accountId,
                'parent_transaction_id': parentId,
                'is_installment_parent': false,
                'amount': e.amount,
                'description': description,
                'date': e.chargeDate.toIso8601String().split('T')[0],
                'type': 'expense',
                'status': status,
                'currency': currency,
                'num_cuotas': numCuotas,
                'installment_number': e.number,
                'has_interest': hasInterest,
                'interest_rate': hasInterest ? interestRate : null,
                'original_purchase_amount': amount,
                if (categoryId != null) 'category_id': categoryId,
                if (subCategoryId != null) 'sub_category_id': subCategoryId,
                if (expenseGroupId != null) 'expense_group_id': expenseGroupId,
                if (notes != null && notes.isNotEmpty) 'notes': notes,
                if (place != null && place.isNotEmpty) 'place': place,
                if (movementType != null) 'movement_type': movementType,
                'periodo_facturacion': e.billingPeriod,
                'fecha_corte_calculada':
                    e.cutoffDate.toIso8601String().split('T')[0],
                'fecha_pago_calculada':
                    e.paymentDate.toIso8601String().split('T')[0],
              })
          .toList();

      await _client.from('transactions').insert(childRows);
    } catch (e) {
      // Clean up parent if children failed (no DB transactions in Supabase JS client).
      await _client.from('transactions').delete().eq('id', parentId);
      rethrow;
    }

    return parentId;
  }

  /// Updates an installment purchase: patches the parent row, reads the
  /// existing children's statuses to preserve them, deletes all children,
  /// and regenerates the schedule with the new parameters.
  Future<void> updateInstallmentPurchase({
    required String parentId,
    required String accountId,
    required double amount,
    required int numCuotas,
    required bool hasInterest,
    required double interestRate,
    required DateTime purchaseDate,
    required String currency,
    required String description,
    required CreditCardRules rules,
    required Bank bank,
    String? categoryId,
    String? subCategoryId,
    String? expenseGroupId,
    String? notes,
    String? place,
    String? movementType,
    String status = 'paid',
  }) async {
    final userId = _client.auth.currentUser!.id;
    final dateStr =
        '${purchaseDate.year}-${purchaseDate.month.toString().padLeft(2, '0')}-${purchaseDate.day.toString().padLeft(2, '0')}';

    // 1. Preserve statuses that the user may have set on individual cuotas.
    final existingChildren = await _client
        .from('transactions')
        .select('installment_number, status')
        .eq('parent_transaction_id', parentId);
    final Map<int, String> preservedStatuses = {
      for (final row in existingChildren)
        (row['installment_number'] as int): row['status'] as String,
    };

    // 2. Recalculate parent billing info.
    final parentBillingPeriod =
        CreditCardCalculator.determineBillingPeriod(purchaseDate, rules, bank);
    final parts = parentBillingPeriod.split('-');
    final parentCutoff = CreditCardCalculator.calculateCutoffDate(
        rules, bank, int.parse(parts[0]), int.parse(parts[1]));
    final parentPayment =
        CreditCardCalculator.calculatePaymentDate(rules, bank, parentCutoff);

    // 3. Update parent row.
    await _client.from('transactions').update({
      'amount': amount,
      'original_purchase_amount': amount,
      'description': description,
      'date': dateStr,
      'status': status,
      'currency': currency,
      'num_cuotas': numCuotas,
      'has_interest': hasInterest,
      'interest_rate': hasInterest ? interestRate : null,
      'category_id': categoryId,
      'sub_category_id': subCategoryId,
      'expense_group_id': expenseGroupId,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'place': place?.isNotEmpty == true ? place : null,
      'movement_type': movementType,
      'periodo_facturacion': parentBillingPeriod,
      'fecha_corte_calculada':
          parentCutoff.toIso8601String().split('T')[0],
      'fecha_pago_calculada':
          parentPayment.toIso8601String().split('T')[0],
    }).eq('id', parentId);

    // 4. Delete old children (triggers unwind each child's balance one by one).
    await _client
        .from('transactions')
        .delete()
        .eq('parent_transaction_id', parentId);

    // 5. Regenerate and insert new children, restoring statuses by cuota number.
    final schedule = InstallmentCalculator.generateSchedule(
      purchaseDate: purchaseDate,
      rules: rules,
      bank: bank,
      numCuotas: numCuotas,
      hasInterest: hasInterest,
      monthlyRate: interestRate,
      principal: amount,
    );

    final childRows = schedule
        .map((e) => {
              'user_id': userId,
              'account_id': accountId,
              'parent_transaction_id': parentId,
              'is_installment_parent': false,
              'amount': e.amount,
              'description': description,
              'date': e.chargeDate.toIso8601String().split('T')[0],
              'type': 'expense',
              'status': preservedStatuses[e.number] ?? status,
              'currency': currency,
              'num_cuotas': numCuotas,
              'installment_number': e.number,
              'has_interest': hasInterest,
              'interest_rate': hasInterest ? interestRate : null,
              'original_purchase_amount': amount,
              if (categoryId != null) 'category_id': categoryId,
              if (subCategoryId != null) 'sub_category_id': subCategoryId,
              if (expenseGroupId != null) 'expense_group_id': expenseGroupId,
              if (notes != null && notes.isNotEmpty) 'notes': notes,
              if (place != null && place.isNotEmpty) 'place': place,
              if (movementType != null) 'movement_type': movementType,
              'periodo_facturacion': e.billingPeriod,
              'fecha_corte_calculada':
                  e.cutoffDate.toIso8601String().split('T')[0],
              'fecha_pago_calculada':
                  e.paymentDate.toIso8601String().split('T')[0],
            })
        .toList();

    await _client.from('transactions').insert(childRows);
  }

  /// Fetches the parent installment transaction for a given child.
  Future<Transaction?> getInstallmentParent(String parentId) async {
    final data = await _client
        .from('transactions')
        .select()
        .eq('id', parentId)
        .maybeSingle();
    if (data == null) return null;
    return Transaction.fromJson(data);
  }

  /// Fetches all child installment transactions for a given parent, ordered
  /// by installment_number ascending.
  Future<List<Transaction>> getInstallmentChildren(String parentId) async {
    final data = await _client
        .from('transactions')
        .select()
        .eq('parent_transaction_id', parentId)
        .order('installment_number');
    return (data as List<dynamic>)
        .map((json) => Transaction.fromJson(json))
        .toList();
  }

  /// Deletes a transaction. If [id] is an installment parent, the FK
  /// ON DELETE CASCADE automatically removes all child rows; child delete
  /// triggers unwind each child's balance impact individually.
  Future<void> deleteTransaction(String id) async {
    await _client.from('transactions').delete().eq('id', id);
  }

  // Recurring Transactions
  Future<List<RecurringTransaction>> getRecurringTransactions() =>
      _withRetry(() async {
        final userId = _client.auth.currentUser!.id;
        final List<dynamic> data = await _client
            .from('recurring_transactions')
            .select()
            .eq('user_id', userId)
            .order('next_run_date');
        return data.map((json) => RecurringTransaction.fromJson(json)).toList();
      }, 'Error fetching recurring transactions');

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
  Future<List<Map<String, dynamic>>> getYearlySummary(int year) =>
      _withRetry(() async {
        final userId = _client.auth.currentUser!.id;
        final result = await _client
            .from('transactions')
            .select('date, amount, type, currency')
            .eq('user_id', userId)
            .eq('status', 'paid')
            .eq('is_installment_parent', false) // exclude display-only parent rows
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
      }, 'Error fetching yearly summary');

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

  Future<List<String>> getAccountSortOrder() async {
    final userId = _client.auth.currentUser!.id;
    try {
      final data = await _client
          .from('profiles')
          .select('account_sort_order')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return const [];
      final raw = data['account_sort_order'] as List?;
      return raw?.map((e) => e.toString()).toList() ?? const [];
    } on PostgrestException catch (e) {
      throw Exception('Error fetching account sort order: $e');
    } catch (e) {
      throw Exception('Error fetching account sort order: $e');
    }
  }

  Future<void> setAccountSortOrder(List<String> ids) async {
    final userId = _client.auth.currentUser!.id;
    try {
      await _client.from('profiles').upsert({
        'id': userId,
        'account_sort_order': ids,
      });
    } on PostgrestException catch (e) {
      throw Exception('Error updating account sort order: $e');
    } catch (e) {
      throw Exception('Error updating account sort order: $e');
    }
  }
}

