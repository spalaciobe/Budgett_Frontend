import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

class AddAccountDialog extends ConsumerStatefulWidget {
  const AddAccountDialog({super.key});

  @override
  ConsumerState<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _closingDayController = TextEditingController();
  final _paymentDueDayController = TextEditingController();
  
  String _selectedType = 'checking';
  String? _selectedIcon;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    _closingDayController.dispose();
    _paymentDueDayController.dispose();
    super.dispose();
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final accountData = {
      'name': _nameController.text,
      'type': _selectedType,
      'balance': CurrencyFormatter.parse(_balanceController.text),
      'icon': _selectedIcon,
    };

    // Add credit card specific fields
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
    }

    try {
      await ref.read(financeRepositoryProvider).createAccount(accountData);
      
      // Invalidate to refresh
      ref.invalidate(accountsProvider);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully')),
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
                    Text('Add Account', style: Theme.of(context).textTheme.headlineSmall),
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
                    hintText: 'e.g., Bancolombia, Nequi',
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

                // Initial Balance
                TextFormField(
                  controller: _balanceController,
                  decoration: const InputDecoration(
                    labelText: 'Initial Balance',
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
                    DropdownMenuItem(value: 'account_balance', child: Text('🏦 Bank')),
                    DropdownMenuItem(value: 'credit_card', child: Text('💳 Card')),
                    DropdownMenuItem(value: 'money', child: Text('💵 Cash')),
                    DropdownMenuItem(value: 'savings', child: Text('🐷 Savings')),
                    DropdownMenuItem(value: 'trending_up', child: Text('📈 Investment')),
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

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveAccount,
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Create Account'),
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
