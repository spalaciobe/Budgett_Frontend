import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import '../../core/utils/credit_card_calculator.dart';
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
  
  DateTime _selectedDate = DateTime.now();
  String _selectedType = 'expense';
  String? _selectedAccountId;
  String? _selectedTargetAccountId;
  String? _selectedCategoryId; // Stores either CategoryId or SubCategoryId
  String? _selectedExpenseGroupId;
  String? _selectedMovementType;
  
  // New fields
  String _status = 'paid';
  bool _isRecurring = false;
  String _frequency = 'monthly';

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account')),
      );
      return;
    }

    // Validate transfer has target account
    if (_selectedType == 'transfer' && _selectedTargetAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination account for transfer')),
      );
      return;
    }

    final transactionData = <String, dynamic>{
      'account_id': _selectedAccountId,
      'amount': CurrencyFormatter.parse(_amountController.text),
      'description': _descriptionController.text,
      'date': _selectedDate.toIso8601String().split('T')[0],
      'type': _selectedType,
      'status': _status,
    };

    final categories = ref.read(categoriesProvider).value ?? [];
    String? finalCategoryId;
    String? finalSubCategoryId;

    if (_selectedCategoryId != null) {
      // Check if it's a main category
      try {
        final cat = categories.firstWhere((c) => c.id == _selectedCategoryId);
        finalCategoryId = cat.id;
      } catch (_) {
        // Not a main category, check subcategories
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
    // Find selected account object
    try {
      final accounts = ref.read(accountsProvider).value ?? [];
      final account = accounts.firstWhere((a) => a.id == _selectedAccountId);
      
      if (account.type == 'credit_card' && account.creditCardRules != null) {
         try {
           // We try to fetch the bank or fallback
           // ideally we would cache banks or have them in the provider
           final bank = await ref.read(bankRepositoryProvider).getBanks()
              .then((banks) => banks.firstWhere(
                  (b) => b.id == account.creditCardRules!.bankId,
                  orElse: () => Bank(id: '0', name: 'Unknown', code: 'UNK')
              ));
              
           final billingPeriod = CreditCardCalculator.determineBillingPeriod(
                _selectedDate,
                account.creditCardRules!,
                bank
            );

            // Calculate exact dates for that period
            final periodParts = billingPeriod.split('-');
            final periodYear = int.parse(periodParts[0]);
            final periodMonth = int.parse(periodParts[1]);

            final realCutoffDate = CreditCardCalculator.calculateCutoffDate(
                account.creditCardRules!,
                bank,
                periodYear, 
                periodMonth
            );
            
            final realPaymentDate = CreditCardCalculator.calculatePaymentDate(
                account.creditCardRules!,
                bank,
                realCutoffDate
            );

            transactionData['periodo_facturacion'] = billingPeriod;
            transactionData['fecha_corte_calculada'] = realCutoffDate.toIso8601String();
            transactionData['fecha_pago_calculada'] = realPaymentDate.toIso8601String();

         } catch (e) {
           print('Error calculating billing info: $e');
         }
      }
    } catch (_) {}

    try {
      final repo = ref.read(financeRepositoryProvider);
      
      // 1. Add the actual transaction
      await repo.addTransaction(transactionData);
      
      // 2. Add recurring rule if selected
      if (_isRecurring) {
        // Calculate next run date based on frequency
        DateTime nextDate = _selectedDate;
        switch (_frequency) {
          case 'daily': nextDate = nextDate.add(const Duration(days: 1)); break;
          case 'weekly': nextDate = nextDate.add(const Duration(days: 7)); break;
          case 'biweekly': nextDate = nextDate.add(const Duration(days: 14)); break;
          case 'monthly': nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day); break;
          case 'yearly': nextDate = DateTime(nextDate.year + 1, nextDate.month, nextDate.day); break;
        }

        final recurringData = RecurringTransaction(
          id: '', // Generated by backend
          description: _descriptionController.text,
          amount: CurrencyFormatter.parse(_amountController.text),
          categoryId: finalCategoryId,
          accountId: _selectedAccountId,
          type: _selectedType,
          frequency: _frequency,
          nextRunDate: nextDate,
          isActive: true,
        );
        
        await repo.addRecurringTransaction(recurringData);
      }
      
      // Invalidate providers to refresh data
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountsProvider);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isRecurring ? 'Transaction & Recurrence saved' : 'Transaction saved')),
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
    final expenseGroupsAsync = ref.watch(expenseGroupsProvider((month: _selectedDate.month, year: _selectedDate.year)));

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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Add Transaction', style: Theme.of(context).textTheme.headlineSmall),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter()],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (CurrencyFormatter.parse(value) == 0.0 && value != '0' && value != '0.0') return 'Invalid number';
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
                        'Date: ${DateFormat.yMMMd().format(_selectedDate)}',
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
                
                // Add Simulator here
                if (_selectedAccountId != null && _amountController.text.isNotEmpty) ...[
                   Consumer(
                     builder: (context, ref, _) {
                       final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
                       final account = accounts.firstWhere((a) => a.id == _selectedAccountId, orElse: () => accounts.first); // fallback safe
                       
                       if (account.type == 'credit_card' && account.creditCardRules != null) {
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
                ],

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
                  onChanged: (value) => setState(() => _selectedType = value!),
                ),
                const SizedBox(height: 16),
                
                // Status Toggle
                Row(
                  children: [
                     Expanded(
                       child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'paid', label: Text('Paid'), icon: Icon(Icons.check_circle_outline)),
                          ButtonSegment(value: 'pending', label: Text('Pending'), icon: Icon(Icons.pending_outlined)),
                        ],
                        selected: {_status},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _status = newSelection.first;
                          });
                        },
                      ),
                     ),
                  ],
                ),
                const SizedBox(height: 16),

                // Recurrence Switch
                SwitchListTile(
                  title: const Text('Is Recurring?'),
                  subtitle: const Text('Automatically creates future transactions'),
                  value: _isRecurring,
                  onChanged: (bool value) {
                    setState(() {
                      _isRecurring = value;
                    });
                  },
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
                      DropdownMenuItem(value: 'biweekly', child: Text('Bi-Weekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                    ],
                    onChanged: (value) => setState(() => _frequency = value!),
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
                    items: accounts.map((acc) => DropdownMenuItem(
                      value: acc.id,
                      child: Text(acc.name),
                    )).toList(),
                    onChanged: (value) => setState(() => _selectedAccountId = value),
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (e, s) => Text('Error loading accounts: $e'),
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
                        if (cat.subCategories != null && cat.subCategories!.isNotEmpty) {
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
                        onChanged: (value) => setState(() => _selectedCategoryId = value),
                      );
                    },
                    loading: () => const CircularProgressIndicator(),
                    error: (e, s) => Text('Error loading categories: $e'),
                  ),
                if (_selectedType != 'transfer') const SizedBox(height: 16),

                // Target Account (only for transfers)
                if (_selectedType == 'transfer')
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
                      onChanged: (value) => setState(() => _selectedTargetAccountId = value),
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (e, s) => Text('Error loading accounts: $e'),
                  ),
                if (_selectedType == 'transfer') const SizedBox(height: 16),

                // Movement Type (for expenses)
                if (_selectedType == 'expense')
                  DropdownButtonFormField<String>(
                    value: _selectedMovementType,
                    decoration: const InputDecoration(
                      labelText: 'Movement Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed Expense')),
                      DropdownMenuItem(value: 'variable', child: Text('Variable Expense')),
                    ],
                    onChanged: (value) => setState(() => _selectedMovementType = value),
                  ),
                if (_selectedType == 'expense') const SizedBox(height: 16),

                // Expense Group (Optional, only for expenses)
                if (_selectedType == 'expense')
                  expenseGroupsAsync.when(
                    data: (groups) => DropdownButtonFormField<String?>(
                      value: _selectedExpenseGroupId,
                      decoration: const InputDecoration(
                        labelText: 'Expense Group (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('None')),
                        ...groups.map((ExpenseGroup g) => DropdownMenuItem<String?>(
                          value: g.id, 
                          child: Text(g.name),
                        )),
                      ],
                      onChanged: (value) => setState(() => _selectedExpenseGroupId = value),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_,__) => const SizedBox(),
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
