import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

class EditAccountDialog extends ConsumerStatefulWidget {
  final Account account;

  const EditAccountDialog({super.key, required this.account});

  @override
  ConsumerState<EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends ConsumerState<EditAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _balanceController;
  late TextEditingController _creditLimitController;
  late TextEditingController _closingDayController;
  late TextEditingController _paymentDueDayController;
  
  late String _selectedType;
  String? _selectedIcon;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final acc = widget.account;
    _nameController = TextEditingController(text: acc.name);
    _balanceController = TextEditingController(text: CurrencyFormatter.format(acc.balance, includeSymbol: false));
    _creditLimitController = TextEditingController(text: CurrencyFormatter.format(acc.creditLimit, includeSymbol: false));
    _closingDayController = TextEditingController(text: acc.closingDay?.toString() ?? '');
    _paymentDueDayController = TextEditingController(text: acc.paymentDueDay?.toString() ?? '');
    
    _selectedType = acc.type;
    _selectedIcon = acc.icon;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    _closingDayController.dispose();
    _paymentDueDayController.dispose();
    super.dispose();
  }

  Future<void> _updateAccount() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    final accountData = <String, dynamic>{
      'name': _nameController.text,
      'type': _selectedType,
      'balance': CurrencyFormatter.parse(_balanceController.text), // Allows manual adjustment/reconciliation
      'icon': _selectedIcon,
    };

    if (_selectedType == 'credit_card') {
      accountData['credit_limit'] = _creditLimitController.text.isEmpty 
          ? 0.0 
          : CurrencyFormatter.parse(_creditLimitController.text);
      accountData['closing_day'] = _closingDayController.text.isEmpty 
          ? null 
          : int.parse(_closingDayController.text);
      accountData['payment_due_day'] = _paymentDueDayController.text.isEmpty 
          ? null 
          : int.parse(_paymentDueDayController.text);
    } else {
      // Clear credit card specific fields if type changed
      accountData['credit_limit'] = 0.0;
      accountData['closing_day'] = null;
      accountData['payment_due_day'] = null;
    }

    try {
      await ref.read(financeRepositoryProvider).updateAccount(widget.account.id, accountData);
      
      ref.invalidate(accountsProvider);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account updated successfully')),
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

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text('Are you sure you want to delete "${widget.account.name}"? This heavily impacts your records and might delete all associated transactions.'),
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
      await ref.read(financeRepositoryProvider).deleteAccount(widget.account.id);
      
      ref.invalidate(accountsProvider);
      ref.invalidate(recentTransactionsProvider); // Transactions might be gone
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted successfully')),
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
    final isCreditCard = _selectedType == 'credit_card';

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
                    Text('Edit Account', style: Theme.of(context).textTheme.headlineSmall),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Account Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // Type
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Account Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'checking', child: Text('Checking')),
                    DropdownMenuItem(value: 'savings', child: Text('Savings')),
                    DropdownMenuItem(value: 'credit_card', child: Text('Credit Card')),
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'investment', child: Text('Investment')),
                  ],
                  onChanged: (value) => setState(() => _selectedType = value!),
                ),
                const SizedBox(height: 16),

                // Balance
                TextFormField(
                  controller: _balanceController,
                  decoration: const InputDecoration(
                    labelText: 'Current Balance',
                    helperText: 'Adjust to reconcile with bank',
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

                // Icon selector
                DropdownButtonFormField<String>(
                  value: _selectedIcon,
                  decoration: const InputDecoration(
                    labelText: 'Icon (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Default')),
                    DropdownMenuItem(value: 'account_balance', child: Row(children: [Icon(Icons.account_balance, size: 18), SizedBox(width: 8), Text('Bank')])),
                    DropdownMenuItem(value: 'credit_card', child: Row(children: [Icon(Icons.credit_card, size: 18), SizedBox(width: 8), Text('Card')])),
                    DropdownMenuItem(value: 'money', child: Row(children: [Icon(Icons.money, size: 18), SizedBox(width: 8), Text('Cash')])),
                    DropdownMenuItem(value: 'savings', child: Row(children: [Icon(Icons.savings, size: 18), SizedBox(width: 8), Text('Savings')])),
                    DropdownMenuItem(value: 'trending_up', child: Row(children: [Icon(Icons.trending_up, size: 18), SizedBox(width: 8), Text('Investment')])),
                  ],
                  onChanged: (value) => setState(() => _selectedIcon = value),
                ),
                const SizedBox(height: 16),

                // Credit Card specific fields
                if (isCreditCard) ...[
                  const Divider(),
                  Text('Credit Card Details', 
                    style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _creditLimitController,
                    decoration: const InputDecoration(
                      labelText: 'Credit Limit',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [CurrencyInputFormatter()],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _closingDayController,
                          decoration: const InputDecoration(
                            labelText: 'Closing Day',
                            border: OutlineInputBorder(),
                            hintText: '1-31',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _paymentDueDayController,
                          decoration: const InputDecoration(
                            labelText: 'Payment Due Day',
                            border: OutlineInputBorder(),
                            hintText: '1-31',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading ? null : _deleteAccount,
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
                          onPressed: _isLoading ? null : _updateAccount,
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
      ),
    );
  }
}
