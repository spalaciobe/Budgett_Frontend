import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import '../../data/repositories/broker_repository.dart';
import '../../data/models/broker_model.dart';
import '../../data/models/investment_details_model.dart';
import 'add_account_dialog.dart' show buildInvestmentDetailsMap;

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
  late TextEditingController _balanceUsdController;
  late TextEditingController _creditLimitUsdController;
  late TextEditingController _closingDayController;
  late TextEditingController _paymentDueDayController;

  // Investment controllers
  late TextEditingController _apyRateController;
  late TextEditingController _principalController;
  late TextEditingController _interestRateController;
  late TextEditingController _termDaysController;
  late TextEditingController _fundCodeController;

  late String _selectedType;
  String? _selectedIcon;

  // Investment state
  InvestmentType _selectedInvestmentType = InvestmentType.highYield;
  String _investmentBaseCurrency = 'COP';
  Broker? _selectedBroker;
  String _investmentInterestPeriod = 'monthly';
  DateTime? _cdtStartDate;
  DateTime? _cdtMaturityDate;
  DateTime? _highYieldLastInterestDate;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final acc = widget.account;
    _nameController = TextEditingController(text: acc.name);
    _balanceController = TextEditingController(text: CurrencyFormatter.format(acc.balance, includeSymbol: false));
    _creditLimitController = TextEditingController(text: CurrencyFormatter.format(acc.creditLimit, includeSymbol: false));
    _balanceUsdController = TextEditingController(
      text: acc.balanceUsd != 0.0 ? CurrencyFormatter.format(acc.balanceUsd, includeSymbol: false, currency: 'USD') : '',
    );
    _creditLimitUsdController = TextEditingController(
      text: acc.creditLimitUsd != 0.0 ? CurrencyFormatter.format(acc.creditLimitUsd, includeSymbol: false, currency: 'USD') : '',
    );
    _closingDayController = TextEditingController(text: acc.closingDay?.toString() ?? '');
    _paymentDueDayController = TextEditingController(text: acc.paymentDueDay?.toString() ?? '');

    _selectedType = acc.type;
    _selectedIcon = acc.icon;

    // Investment fields — initialise from existing details if present
    final inv = acc.investmentDetails;
    _apyRateController = TextEditingController(
      text: inv?.apyRate != null ? (inv!.apyRate! * 100).toStringAsFixed(2) : '',
    );
    _principalController = TextEditingController(
      text: inv?.principal != null
          ? CurrencyFormatter.format(inv!.principal!, includeSymbol: false)
          : '',
    );
    _interestRateController = TextEditingController(
      text: inv?.interestRate != null ? (inv!.interestRate! * 100).toStringAsFixed(2) : '',
    );
    _termDaysController = TextEditingController(text: inv?.termDays?.toString() ?? '');
    _fundCodeController = TextEditingController(text: inv?.fundCode ?? '');

    if (inv != null) {
      _selectedInvestmentType = inv.investmentType;
      _investmentBaseCurrency = inv.baseCurrency;
      _investmentInterestPeriod = inv.interestPeriod ?? 'monthly';
      _cdtStartDate = inv.startDate;
      _cdtMaturityDate = inv.maturityDate;
      _highYieldLastInterestDate = inv.lastInterestDate;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    _balanceUsdController.dispose();
    _creditLimitUsdController.dispose();
    _closingDayController.dispose();
    _paymentDueDayController.dispose();
    _apyRateController.dispose();
    _principalController.dispose();
    _interestRateController.dispose();
    _termDaysController.dispose();
    _fundCodeController.dispose();
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
      accountData['balance_usd'] = _balanceUsdController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_balanceUsdController.text, currency: 'USD');
      accountData['credit_limit_usd'] = _creditLimitUsdController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_creditLimitUsdController.text, currency: 'USD');
      accountData['closing_day'] = _closingDayController.text.isEmpty
          ? null
          : int.parse(_closingDayController.text);
      accountData['payment_due_day'] = _paymentDueDayController.text.isEmpty
          ? null
          : int.parse(_paymentDueDayController.text);
    } else if (_selectedType == 'investment') {
      // Clear CC-specific fields
      accountData['credit_limit'] = 0.0;
      accountData['closing_day'] = null;
      accountData['payment_due_day'] = null;

      // Apply USD balance if base currency is USD
      if (_investmentBaseCurrency == 'USD') {
        accountData['balance_usd'] =
            CurrencyFormatter.parse(_balanceController.text, currency: 'USD');
        accountData['balance'] = 0.0;
      } else {
        accountData['balance_usd'] = 0.0;
        accountData['credit_limit_usd'] = 0.0;
      }

      accountData['investment_details'] = buildInvestmentDetailsMap(
        investmentType: _selectedInvestmentType,
        brokerId: _selectedBroker?.id ?? widget.account.investmentDetails?.brokerId,
        baseCurrency: _investmentBaseCurrency,
        apyRate: double.tryParse(_apyRateController.text) != null
            ? double.parse(_apyRateController.text) / 100
            : widget.account.investmentDetails?.apyRate,
        interestPeriod: _investmentInterestPeriod,
        lastInterestDate: _highYieldLastInterestDate,
        principal: _principalController.text.isEmpty
            ? widget.account.investmentDetails?.principal
            : CurrencyFormatter.parse(_principalController.text),
        interestRate: double.tryParse(_interestRateController.text) != null
            ? double.parse(_interestRateController.text) / 100
            : widget.account.investmentDetails?.interestRate,
        termDays: int.tryParse(_termDaysController.text) ??
            widget.account.investmentDetails?.termDays,
        startDate: _cdtStartDate,
        maturityDate: _cdtMaturityDate,
        fundCode: _fundCodeController.text.trim().isEmpty
            ? null
            : _fundCodeController.text.trim(),
      );
    } else {
      // Clear credit card specific fields if type changed
      accountData['credit_limit'] = 0.0;
      accountData['balance_usd'] = 0.0;
      accountData['credit_limit_usd'] = 0.0;
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

  void _autoComputeMaturity() {
    final start = _cdtStartDate;
    final days = int.tryParse(_termDaysController.text);
    if (start != null && days != null) {
      setState(() => _cdtMaturityDate = start.add(Duration(days: days)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreditCard = _selectedType == 'credit_card';
    final isInvestment = _selectedType == 'investment';
    final brokersAsync = ref.watch(brokersFutureProvider);

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
                  inputFormatters: [const CurrencyInputFormatter()],
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
                      labelText: 'Total Credit Limit (COP)',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [const CurrencyInputFormatter()],
                  ),
                  const SizedBox(height: 16),

                  // USD slice
                  const Divider(),
                  Text('USD Balance',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _balanceUsdController,
                    decoration: const InputDecoration(
                      labelText: 'USD Balance (negative if debt)',
                      prefixText: 'US\$',
                      border: OutlineInputBorder(),
                      helperText: 'Adjust manually to reconcile with bank.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    inputFormatters: [const CurrencyInputFormatter(currency: 'USD')],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _creditLimitUsdController,
                    decoration: const InputDecoration(
                      labelText: 'USD Credit Limit',
                      prefixText: 'US\$',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [const CurrencyInputFormatter(currency: 'USD')],
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

                // ── Investment section ────────────────────────────────────
                if (isInvestment) ...[
                  const Divider(),
                  Text('Investment Details',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<InvestmentType>(
                    value: _selectedInvestmentType,
                    decoration: const InputDecoration(
                      labelText: 'Investment Type',
                      border: OutlineInputBorder(),
                    ),
                    items: InvestmentType.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.displayName),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedInvestmentType = v!;
                      _investmentBaseCurrency =
                          v == InvestmentType.stockEtf ? 'USD' : 'COP';
                    }),
                  ),
                  const SizedBox(height: 12),

                  brokersAsync.when(
                    data: (brokers) {
                      final filtered = brokers
                          .where((b) => b.supportedTypes.contains(
                              _selectedInvestmentType.toDbString()))
                          .toList();
                      return DropdownButtonFormField<Broker>(
                        value: _selectedBroker,
                        decoration: const InputDecoration(
                          labelText: 'Platform / Broker',
                          border: OutlineInputBorder(),
                        ),
                        items: filtered
                            .map((b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(b.name),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedBroker = v),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error: $e'),
                  ),
                  const SizedBox(height: 12),

                  if (_selectedInvestmentType == InvestmentType.highYield) ...[
                    TextFormField(
                      controller: _apyRateController,
                      decoration: const InputDecoration(
                        labelText: 'APY (E.A. %)',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _highYieldLastInterestDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _highYieldLastInterestDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Last interest recorded',
                          border: const OutlineInputBorder(),
                          suffixIcon: _highYieldLastInterestDate != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(
                                      () => _highYieldLastInterestDate = null),
                                )
                              : const Icon(Icons.calendar_today, size: 18),
                          helperText:
                              'If changing the APY, record interest first then update here.',
                        ),
                        child: Text(
                          _highYieldLastInterestDate != null
                              ? DateFormat('MMM d, y')
                                  .format(_highYieldLastInterestDate!)
                              : 'Not set',
                          style: _highYieldLastInterestDate == null
                              ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.45),
                                  )
                              : null,
                        ),
                      ),
                    ),
                  ],

                  if (_selectedInvestmentType == InvestmentType.cdt) ...[
                    TextFormField(
                      controller: _principalController,
                      decoration: const InputDecoration(
                        labelText: 'Principal Amount',
                        prefixText: '\$',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [const CurrencyInputFormatter()],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _interestRateController,
                            decoration: const InputDecoration(
                              labelText: 'Annual Rate (%)',
                              suffixText: '%',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _termDaysController,
                            decoration: const InputDecoration(
                              labelText: 'Term (days)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _autoComputeMaturity(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _cdtMaturityDate ??
                              DateTime.now().add(const Duration(days: 180)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                        );
                        if (picked != null) {
                          setState(() => _cdtMaturityDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Maturity Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.event_available, size: 18),
                        ),
                        child: Text(
                          _cdtMaturityDate != null
                              ? '${_cdtMaturityDate!.year}-${_cdtMaturityDate!.month.toString().padLeft(2, '0')}-${_cdtMaturityDate!.day.toString().padLeft(2, '0')}'
                              : 'Select date',
                        ),
                      ),
                    ),
                  ],

                  if (_selectedInvestmentType == InvestmentType.fic) ...[
                    TextFormField(
                      controller: _fundCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Fund Code (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
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
