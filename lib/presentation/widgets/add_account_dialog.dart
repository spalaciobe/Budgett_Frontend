import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import '../../data/repositories/bank_repository.dart';
import '../../data/models/bank_model.dart';

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
  
  // Credit Card Controllers
  final _cutoffDayController = TextEditingController(); // For Fixed
  final _paymentDayController = TextEditingController(); // For Fixed
  // For Relative (e.g. RappiCard uses fixed logic for internal display maybe, but actually relative)
  
  String _selectedType = 'checking';
  String? _selectedIcon;
  Bank? _selectedBank;
  
  // Custom Config logic
  bool _useBankDefaults = true;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    _cutoffDayController.dispose();
    _paymentDayController.dispose();
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
      
      if (_selectedBank != null) {
        final rules = <String, dynamic>{
          'banco_id': _selectedBank!.id,
          'tipo_corte': _selectedBank!.name == 'RappiCard' ? 'relativo' : 'fijo', // Logic simplification for demo
          'tipo_pago': _selectedBank!.name == 'RappiCard' ? 'relativo_dias' : 'fijo',
        };

        if (_selectedBank!.name == 'RappiCard') {
            rules['corte_relativo_tipo'] = 'penultimo_dia_habil';
            rules['dias_despues_corte'] = 10;
            rules['tipo_offset_pago'] = 'calendario';
        } else {
             // Fixed (Bancolombia, etc.)
             rules['dia_corte_nominal'] = int.parse(_cutoffDayController.text.isEmpty ? '15' : _cutoffDayController.text);
             rules['dia_pago_nominal'] = int.parse(_paymentDayController.text.isEmpty ? '30' : _paymentDayController.text);
             rules['mes_pago'] = 'mismo'; // Default simplification
        }
        
        accountData['credit_card_details'] = rules;
      }
    }

    try {
      await ref.read(financeRepositoryProvider).createAccount(accountData);
      
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
    final banksAsync = ref.watch(banksFutureProvider);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
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
                  onChanged: (value) => setState(() {
                    _selectedType = value!;
                    if (value == 'credit_card') {
                       _selectedIcon = 'credit_card';
                    }
                  }),
                ),
                const SizedBox(height: 16),

                // Initial Balance
                TextFormField(
                  controller: _balanceController,
                  decoration: const InputDecoration(
                    labelText: 'Initial Balance / Current Debt (Negative)',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                    helperText: 'For credit cards, enter negative value if you have debt.'
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: [CurrencyInputFormatter()],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
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
                  
                  // Bank Selector
                  banksAsync.when(
                    data: (banks) => DropdownButtonFormField<Bank>(
                      value: _selectedBank,
                      decoration: const InputDecoration(
                        labelText: 'Bank',
                        border: OutlineInputBorder(),
                      ),
                      items: banks.map((bank) => DropdownMenuItem(
                        value: bank,
                        child: Text(bank.name),
                      )).toList(),
                      onChanged: (value) => setState(() {
                        _selectedBank = value;
                        // Defaults
                        if (value?.code == 'RAPPICARD') {
                           // Set defaults for Rappi (hidden logic)
                        }
                      }),
                      validator: (value) => value == null ? 'Required' : null,
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (e, s) => Text('Error loading banks: $e'),
                  ),
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

                  if (_selectedBank != null && _selectedBank!.code != 'RAPPICARD') ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cutoffDayController,
                              decoration: const InputDecoration(
                                labelText: 'Cutoff Day',
                                border: OutlineInputBorder(),
                                hintText: '1-31',
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _paymentDayController,
                              decoration: const InputDecoration(
                                labelText: 'Payment Day',
                                border: OutlineInputBorder(),
                                hintText: '1-31',
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                       const SizedBox(height: 8),
                       Text('For ${_selectedBank!.name}, weekends/holidays will be adjusted automatically.', 
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                   ],
                   if (_selectedBank != null && _selectedBank!.code == 'RAPPICARD') ...[
                     const Card(
                       child: Padding(
                         padding: EdgeInsets.all(12.0),
                         child: Column(
                           children: [
                             Text('RappiCard Strategy', style: TextStyle(fontWeight: FontWeight.bold)),
                             Text('Cutoff: Penultimate business day'),
                             Text('Payment: 10 days after cutoff'),
                             Text('Dates are calculated automatically.'),
                           ],
                         ),
                       ),
                     )
                   ]
                ],

                const SizedBox(height: 24),
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
