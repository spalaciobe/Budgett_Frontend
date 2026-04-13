import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import '../../core/utils/credit_card_calculator.dart';
import '../../data/models/account_model.dart';
import '../../data/models/bank_model.dart';
import '../../data/repositories/bank_repository.dart';
import 'package:budgett_frontend/presentation/widgets/credit_card_billing_simulator.dart';
import 'package:intl/intl.dart';

class AddTransactionDialog extends ConsumerStatefulWidget {
  const AddTransactionDialog({super.key});

  @override
  ConsumerState<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends ConsumerState<AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _fxRateController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String _selectedType = 'expense';
  String? _selectedAccountId;
  String? _selectedTargetAccountId;
  String? _selectedCategoryId;
  String? _selectedExpenseGroupId;
  String? _selectedMovementType;

  String _status = 'paid';
  bool _isRecurring = false;
  String _frequency = 'monthly';

  // Currency fields
  String _currency = 'COP';
  bool _isUsdPayment = false; // cross-currency CC payment

  Account? get _selectedAccount {
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    if (_selectedAccountId == null) return null;
    try {
      return accounts.firstWhere((a) => a.id == _selectedAccountId);
    } catch (_) {
      return null;
    }
  }

  Account? get _selectedTargetAccount {
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    if (_selectedTargetAccountId == null) return null;
    try {
      return accounts.firstWhere((a) => a.id == _selectedTargetAccountId);
    } catch (_) {
      return null;
    }
  }

  bool get _isCreditCardExpense =>
      (_selectedType == 'expense' || _selectedType == 'income') &&
      (_selectedAccount?.type == 'credit_card');

  bool get _showUsdPaymentSection =>
      _selectedType == 'transfer' &&
      _selectedTargetAccount?.type == 'credit_card' &&
      (_selectedTargetAccount?.balanceUsd != 0 ||
          _selectedTargetAccount?.creditLimitUsd != 0);

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _fxRateController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged(String newCurrency) {
    setState(() {
      _currency = newCurrency;
      _amountController.clear();
    });
  }

  double? get _usdApplied {
    final amount = CurrencyFormatter.parse(_amountController.text);
    final rate = double.tryParse(_fxRateController.text.replaceAll(',', ''));
    if (amount > 0 && rate != null && rate > 0) return amount / rate;
    return null;
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account')),
      );
      return;
    }

    if (_selectedType == 'transfer' && _selectedTargetAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the destination account')),
      );
      return;
    }

    if (_isUsdPayment) {
      final rate = double.tryParse(_fxRateController.text.replaceAll(',', ''));
      if (rate == null || rate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid exchange rate')),
        );
        return;
      }
    }

    final transactionData = <String, dynamic>{
      'account_id': _selectedAccountId,
      'amount': CurrencyFormatter.parse(_amountController.text, currency: _currency),
      'description': _descriptionController.text,
      'date': _selectedDate.toIso8601String().split('T')[0],
      'type': _selectedType,
      'status': _status,
      'currency': _currency,
    };

    // Cross-currency transfer fields
    if (_isUsdPayment && _selectedType == 'transfer') {
      final rate = double.parse(_fxRateController.text.replaceAll(',', ''));
      transactionData['target_currency'] = 'USD';
      transactionData['fx_rate'] = rate;
    }

    final categories = ref.read(categoriesProvider).value ?? [];
    String? finalCategoryId;
    String? finalSubCategoryId;

    if (_selectedCategoryId != null) {
      try {
        final cat = categories.firstWhere((c) => c.id == _selectedCategoryId);
        finalCategoryId = cat.id;
      } catch (_) {
        for (final cat in categories) {
          if (cat.subCategories != null) {
            try {
              final sub = cat.subCategories!.firstWhere((s) => s.id == _selectedCategoryId);
              finalCategoryId = cat.id;
              finalSubCategoryId = sub.id;
              break;
            } catch (_) {}
          }
        }
      }
    }

    if (finalCategoryId != null) {
      transactionData['category_id'] = finalCategoryId;
      if (finalSubCategoryId != null) {
        transactionData['sub_category_id'] = finalSubCategoryId;
      }
    }

    if (transactionData['category_id'] != null && _selectedExpenseGroupId != null) {
      transactionData['expense_group_id'] = _selectedExpenseGroupId;
    }
    if (_selectedTargetAccountId != null) {
      transactionData['target_account_id'] = _selectedTargetAccountId;
    }
    if (_selectedMovementType != null) {
      transactionData['movement_type'] = _selectedMovementType;
    }
    if (_notesController.text.isNotEmpty) {
      transactionData['notes'] = _notesController.text;
    }

    // Credit Card Billing Period Calculation
    try {
      final accounts = ref.read(accountsProvider).value ?? [];
      final account = accounts.firstWhere((a) => a.id == _selectedAccountId);

      if (account.type == 'credit_card' && account.creditCardRules != null) {
        try {
          final bank = await ref.read(bankRepositoryProvider).getBanks().then(
              (banks) => banks.firstWhere(
                    (b) => b.id == account.creditCardRules!.bankId,
                    orElse: () => Bank(id: '0', name: 'Unknown', code: 'UNK'),
                  ));

          final billingPeriod = CreditCardCalculator.determineBillingPeriod(
              _selectedDate, account.creditCardRules!, bank);

          final periodParts = billingPeriod.split('-');
          final periodYear = int.parse(periodParts[0]);
          final periodMonth = int.parse(periodParts[1]);

          final realCutoffDate = CreditCardCalculator.calculateCutoffDate(
              account.creditCardRules!, bank, periodYear, periodMonth);
          final realPaymentDate = CreditCardCalculator.calculatePaymentDate(
              account.creditCardRules!, bank, realCutoffDate);

          transactionData['periodo_facturacion'] = billingPeriod;
          transactionData['fecha_corte_calculada'] = realCutoffDate.toIso8601String();
          transactionData['fecha_pago_calculada'] = realPaymentDate.toIso8601String();
        } catch (e) {
          debugPrint('Error calculating billing info: $e');
        }
      }
    } catch (_) {}

    try {
      final repo = ref.read(financeRepositoryProvider);

      await repo.addTransaction(transactionData);

      if (_isRecurring) {
        DateTime nextDate = _selectedDate;
        switch (_frequency) {
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

        final recurringData = RecurringTransaction(
          id: '',
          description: _descriptionController.text,
          amount: CurrencyFormatter.parse(_amountController.text, currency: _currency),
          categoryId: finalCategoryId,
          accountId: _selectedAccountId,
          type: _selectedType,
          frequency: _frequency,
          nextRunDate: nextDate,
          isActive: true,
          currency: _currency,
        );

        await repo.addRecurringTransaction(recurringData);
      }

      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_isRecurring
                  ? 'Transaction and recurrence saved'
                  : 'Transaction saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final expenseGroupsAsync = ref.watch(expenseGroupsProvider);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Add Transaction',
                          style: Theme.of(context).textTheme.headlineSmall),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Currency toggle (only for CC expense/income)
                if (_isCreditCardExpense) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'COP',
                          label: Text('COP'),
                          icon: Icon(Icons.monetization_on_outlined, size: 16)),
                      ButtonSegment(
                          value: 'USD',
                          label: Text('USD'),
                          icon: Icon(Icons.attach_money, size: 16)),
                    ],
                    selected: {_currency},
                    onSelectionChanged: (s) => _onCurrencyChanged(s.first),
                  ),
                  const SizedBox(height: 12),
                ],

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: CurrencyFormatter.prefixFor(_currency),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter(currency: _currency)],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (CurrencyFormatter.parse(value, currency: _currency) == 0.0 &&
                        value != '0' &&
                        value != '0.0') return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // Date
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date: ${DateFormat('MM/dd/yyyy').format(_selectedDate)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Billing simulator (CC only)
                if (_selectedAccountId != null && _amountController.text.isNotEmpty)
                  Consumer(
                    builder: (context, ref, _) {
                      final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
                      if (_selectedAccountId == null) return const SizedBox();
                      final account = accounts.firstWhereOrNull(
                          (a) => a.id == _selectedAccountId);
                      if (account == null) return const SizedBox();
                      if (account.type == 'credit_card' &&
                          account.creditCardRules != null) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: CreditCardBillingSimulator(
                            account: account,
                            transactionDate: _selectedDate,
                            amount: double.tryParse(_amountController.text),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),

                // Type
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedType = value!;
                    // Reset currency to COP when not a CC expense
                    if (!_isCreditCardExpense) _currency = 'COP';
                    _isUsdPayment = false;
                  }),
                ),
                const SizedBox(height: 16),

                // Status Toggle
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'paid',
                        label: Text('Paid'),
                        icon: Icon(Icons.check_circle_outline)),
                    ButtonSegment(
                        value: 'pending',
                        label: Text('Pending'),
                        icon: Icon(Icons.pending_outlined)),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
                const SizedBox(height: 16),

                // Recurrence Switch
                SwitchListTile(
                  title: const Text('Recurring?'),
                  subtitle: const Text('Automatically create future transactions'),
                  value: _isRecurring,
                  onChanged: (v) => setState(() => _isRecurring = v),
                  contentPadding: EdgeInsets.zero,
                ),

                if (_isRecurring) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _frequency,
                    decoration: const InputDecoration(
                      labelText: 'Frequency',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'biweekly', child: Text('Biweekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                    ],
                    onChanged: (v) => setState(() => _frequency = v!),
                  ),
                  const SizedBox(height: 16),
                ],

                // Account
                accountsAsync.when(
                  data: (accounts) => DropdownButtonFormField<String>(
                    value: _selectedAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Account',
                      border: OutlineInputBorder(),
                    ),
                    items: accounts
                        .map((acc) => DropdownMenuItem(
                              value: acc.id,
                              child: Text(acc.name),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      _selectedAccountId = value;
                      // Reset currency when switching accounts
                      _currency = 'COP';
                      _isUsdPayment = false;
                    }),
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (e, s) => Text('Error: $e'),
                ),
                const SizedBox(height: 16),

                // Category (only for income/expense)
                if (_selectedType != 'transfer')
                  categoriesAsync.when(
                    data: (categories) {
                      final filteredCategories = categories
                          .where((cat) => cat.type == _selectedType)
                          .toList();

                      final List<DropdownMenuItem<String>> dropdownItems = [];
                      for (final cat in filteredCategories) {
                        if (cat.subCategories != null &&
                            cat.subCategories!.isNotEmpty) {
                          for (final sub in cat.subCategories!) {
                            dropdownItems.add(DropdownMenuItem(
                              value: sub.id,
                              child: Text('${cat.name} > ${sub.name}'),
                            ));
                          }
                        } else {
                          dropdownItems.add(DropdownMenuItem(
                            value: cat.id,
                            child: Text(cat.name),
                          ));
                        }
                      }

                      return DropdownButtonFormField<String>(
                        value: _selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: dropdownItems,
                        onChanged: (v) => setState(() => _selectedCategoryId = v),
                      );
                    },
                    loading: () => const CircularProgressIndicator(),
                    error: (e, s) => Text('Error: $e'),
                  ),
                if (_selectedType != 'transfer') const SizedBox(height: 16),

                // Target Account (for transfers)
                if (_selectedType == 'transfer') ...[
                  accountsAsync.when(
                    data: (accounts) => DropdownButtonFormField<String>(
                      value: _selectedTargetAccountId,
                      decoration: const InputDecoration(
                        labelText: 'Destination Account',
                        border: OutlineInputBorder(),
                      ),
                      items: accounts
                          .where((acc) => acc.id != _selectedAccountId)
                          .map((acc) => DropdownMenuItem(
                                value: acc.id,
                                child: Text(acc.name),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() {
                        _selectedTargetAccountId = value;
                        _isUsdPayment = false;
                      }),
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (e, s) => Text('Error: $e'),
                  ),
                  const SizedBox(height: 16),

                  // USD payment section (transfer to CC with USD balance)
                  if (_showUsdPaymentSection) ...[
                    CheckboxListTile(
                      title: const Text('USD Balance Payment'),
                      subtitle: const Text('Pays down your USD debt'),
                      value: _isUsdPayment,
                      onChanged: (v) => setState(() {
                        _isUsdPayment = v ?? false;
                        if (!_isUsdPayment) _fxRateController.clear();
                      }),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_isUsdPayment) ...[
                      TextFormField(
                        controller: _fxRateController,
                        decoration: const InputDecoration(
                          labelText: 'Exchange Rate (COP per 1 USD)',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. 4200',
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (!_isUsdPayment) return null;
                          final rate = double.tryParse(
                              v?.replaceAll(',', '') ?? '');
                          if (rate == null || rate <= 0) {
                            return 'Enter a valid rate greater than 0';
                          }
                          return null;
                        },
                      ),
                      if (_usdApplied != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'USD applied: ${CurrencyFormatter.format(_usdApplied!, currency: 'USD')}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ],
                ],

                // Movement Type (for expenses)
                if (_selectedType == 'expense') ...[
                  DropdownButtonFormField<String>(
                    value: _selectedMovementType,
                    decoration: const InputDecoration(
                      labelText: 'Movement Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed Expense')),
                      DropdownMenuItem(
                          value: 'variable', child: Text('Variable Expense')),
                    ],
                    onChanged: (v) => setState(() => _selectedMovementType = v),
                  ),
                  const SizedBox(height: 16),
                ],

                // Expense Group (Optional, only for expenses)
                if (_selectedType == 'expense')
                  expenseGroupsAsync.when(
                    data: (groups) => DropdownButtonFormField<String?>(
                      value: _selectedExpenseGroupId,
                      decoration: const InputDecoration(
                        labelText: 'Expense Group (optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('None')),
                        ...groups.map((ExpenseGroup g) =>
                            DropdownMenuItem<String?>(
                                value: g.id, child: Text(g.name))),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedExpenseGroupId = v),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox(),
                  ),
                if (_selectedType == 'expense') const SizedBox(height: 16),

                // Notes
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveTransaction,
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Save Transaction'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
