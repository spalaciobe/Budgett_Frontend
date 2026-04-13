import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';
import 'package:budgett_frontend/core/utils/credit_card_calculator.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

class EditTransactionDialog extends ConsumerStatefulWidget {
  final Transaction transaction;

  const EditTransactionDialog({super.key, required this.transaction});

  @override
  ConsumerState<EditTransactionDialog> createState() => _EditTransactionDialogState();
}

class _EditTransactionDialogState extends ConsumerState<EditTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;
  late TextEditingController _notesController;
  
  late DateTime _selectedDate;
  late String _selectedType;
  String? _selectedAccountId;
  String? _selectedTargetAccountId;
  String? _selectedCategoryId;
  String? _selectedMovementType;
  late String _status;
  late String _currency;
  bool _isUsdPayment = false;
  late TextEditingController _fxRateController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _currency = t.currency;
    _amountController = TextEditingController(
        text: CurrencyFormatter.format(t.amount, includeSymbol: false, currency: t.currency));
    _descriptionController = TextEditingController(text: t.description);
    _notesController = TextEditingController(text: t.notes ?? '');
    _fxRateController = TextEditingController(
        text: t.fxRate != null ? t.fxRate!.toStringAsFixed(0) : '');

    _selectedDate = t.date;
    _selectedType = t.type;
    _selectedAccountId = t.accountId;
    _selectedTargetAccountId = t.targetAccountId;
    _selectedCategoryId = t.subCategoryId ?? t.categoryId;
    _selectedMovementType = t.movementType;
    _status = t.status;
    _isUsdPayment = t.isCrossCurrencyPayment;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _fxRateController.dispose();
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

  Future<void> _updateTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account')),
      );
      return;
    }

    if (_selectedType == 'transfer' && _selectedTargetAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination account for transfer')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final transactionData = <String, dynamic>{
      'account_id': _selectedAccountId,
      'amount': CurrencyFormatter.parse(_amountController.text, currency: _currency),
      'description': _descriptionController.text,
      'date': _selectedDate.toIso8601String().split('T')[0],
      'type': _selectedType,
      'status': _status,
      'currency': _currency,
      'target_account_id': _selectedType == 'transfer' ? _selectedTargetAccountId : null,
      'movement_type': _selectedType == 'expense' ? _selectedMovementType : null,
      'notes': _notesController.text.isNotEmpty ? _notesController.text : null,
    };

    // Cross-currency payment fields
    if (_isUsdPayment && _selectedType == 'transfer') {
      final rate = double.tryParse(_fxRateController.text.replaceAll(',', ''));
      if (rate != null && rate > 0) {
        transactionData['target_currency'] = 'USD';
        transactionData['fx_rate'] = rate;
      }
    } else {
      transactionData['target_currency'] = null;
      transactionData['fx_rate'] = null;
    }

    // Recalculate billing period for CC transactions
    try {
      final accounts = ref.read(accountsProvider).valueOrNull ?? [];
      final account = accounts.firstWhereOrNull((a) => a.id == _selectedAccountId);
      if (account != null && account.type == 'credit_card' && account.creditCardRules != null) {
        final bank = await ref.read(bankRepositoryProvider).getBanks().then(
            (banks) => banks.firstWhereOrNull((b) => b.id == account.creditCardRules!.bankId));
        if (bank != null) {
          final billingPeriod = CreditCardCalculator.determineBillingPeriod(
              _selectedDate, account.creditCardRules!, bank);
          final parts = billingPeriod.split('-');
          final cutoff = CreditCardCalculator.calculateCutoffDate(
              account.creditCardRules!, bank, int.parse(parts[0]), int.parse(parts[1]));
          final payment = CreditCardCalculator.calculatePaymentDate(
              account.creditCardRules!, bank, cutoff);
          transactionData['periodo_facturacion'] = billingPeriod;
          transactionData['fecha_corte_calculada'] = cutoff.toIso8601String();
          transactionData['fecha_pago_calculada'] = payment.toIso8601String();
        }
      }
    } catch (_) {}
    
    // Logic to distinguish Category vs SubCategory ID (Unified Dropdown)
    if (_selectedType != 'transfer' && _selectedCategoryId != null) {
        final categories = ref.read(categoriesProvider).value ?? [];
        String? finalCategoryId;
        String? finalSubCategoryId;

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
        
        if (finalCategoryId != null) {
          transactionData['category_id'] = finalCategoryId;
          transactionData['sub_category_id'] = finalSubCategoryId; // Can be null
        }
    } else {
       transactionData['category_id'] = null;
       transactionData['sub_category_id'] = null;
    }

    try {
      await ref.read(financeRepositoryProvider).updateTransaction(widget.transaction.id, transactionData);
      
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(budgetsProvider); // Budgets might change
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text('Are you sure you want to delete this transaction? Account balances will be reverted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(financeRepositoryProvider).deleteTransaction(widget.transaction.id);
      
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(budgetsProvider);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Edit Transaction', style: Theme.of(context).textTheme.headlineSmall),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Currency toggle (CC transactions)
                      Builder(builder: (context) {
                        final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
                        final account = accounts.firstWhereOrNull(
                            (a) => a.id == _selectedAccountId);
                        final isCC = account?.type == 'credit_card';
                        if (!isCC ||
                            (_selectedType != 'expense' &&
                                _selectedType != 'income')) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'COP', label: Text('COP')),
                              ButtonSegment(value: 'USD', label: Text('USD')),
                            ],
                            selected: {_currency},
                            onSelectionChanged: (s) => setState(() {
                              _currency = s.first;
                              _amountController.clear();
                            }),
                          ),
                        );
                      }),

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
                      InkWell(
                        onTap: () => _selectDate(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedDate.toLocal().toString().split(' ')[0],
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                              const Icon(Icons.calendar_today),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Status
                      DropdownButtonFormField<String>(
                        value: ['paid', 'pending'].contains(_status) ? _status : 'paid',
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                          DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        ],
                        onChanged: (value) => setState(() => _status = value!),
                      ),
                      const SizedBox(height: 16),

                      // Type (Disabled for edit to avoid complex logic changes, or re-enabled if needed)
                      // Allowing type change requires logic to handle "changing from transfer to expense" etc.
                      // For now, let's allow it but fields will update.
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

                      // Category
                      if (_selectedType != 'transfer')
                        categoriesAsync.when(
                          data: (categories) {
                            final filteredCategories = categories.where((cat) => cat.type == _selectedType).toList();
                            
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
                            
                            // Validate selection exists in new list (type change handling)
                            // If simpler check needed:
                            bool selectionExists = dropdownItems.any((item) => item.value == _selectedCategoryId);
                            String? currentValue = selectionExists ? _selectedCategoryId : null;
                            
                            return DropdownButtonFormField<String>(
                              value: currentValue,
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

                      // Target Account
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

                      // Movement Type
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

                      // Notes
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _isLoading ? null : _deleteTransaction,
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _isLoading ? null : _updateTransaction,
                        child: _isLoading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save Changes'),
                      ),
                    ],
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

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
