import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

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
  String? _selectedCategoryId;
  String? _selectedMovementType;

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
      'status': 'paid',
    };

    // Add optional fields only if they have values
    if (_selectedCategoryId != null) {
      transactionData['category_id'] = _selectedCategoryId;
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

    try {
      await ref.read(financeRepositoryProvider).addTransaction(transactionData);
      
      // Invalidate providers to refresh data
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountsProvider);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction added successfully')),
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
                      return DropdownButtonFormField<String>(
                        value: _selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: filteredCategories.map((cat) => DropdownMenuItem(
                          value: cat.id,
                          child: Text(cat.name),
                        )).toList(),
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
