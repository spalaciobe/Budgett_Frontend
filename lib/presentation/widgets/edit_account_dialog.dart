import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
  late TextEditingController _minPaymentCopController;
  late TextEditingController _minPaymentUsdController;

  // Investment controllers
  late TextEditingController _principalController;
  late TextEditingController _interestRateController;
  late TextEditingController _termDaysController;
  late TextEditingController _fundCodeController;

  // Savings APY controller (applies to type='savings', parent or pocket)
  late TextEditingController _apyRateController;

  late String _selectedType;
  String? _selectedIcon;
  Uint8List? _pendingIconBytes;

  // Investment state
  InvestmentType _selectedInvestmentType = InvestmentType.cdt;
  String _investmentBaseCurrency = 'COP';
  Broker? _selectedBroker;
  String _savingsInterestPeriod = 'monthly';
  DateTime? _cdtStartDate;
  DateTime? _cdtMaturityDate;
  DateTime? _savingsLastInterestDate;
  double? _initialApyRate; // decimal form captured on open

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final acc = widget.account;
    _nameController = TextEditingController(text: acc.name);
    // Credit cards store debt as a negative balance; show the positive debt
    // amount so the field is consistent with the "add" dialog.
    final isCc = acc.type == 'credit_card';
    _balanceController = TextEditingController(
      text: CurrencyFormatter.format(isCc ? acc.balance.abs() : acc.balance, includeSymbol: false),
    );
    _creditLimitController = TextEditingController(text: CurrencyFormatter.format(acc.creditLimit, includeSymbol: false));
    _balanceUsdController = TextEditingController(
      text: acc.balanceUsd != 0.0
          ? CurrencyFormatter.format(isCc ? acc.balanceUsd.abs() : acc.balanceUsd, includeSymbol: false, currency: 'USD')
          : '',
    );
    _creditLimitUsdController = TextEditingController(
      text: acc.creditLimitUsd != 0.0 ? CurrencyFormatter.format(acc.creditLimitUsd, includeSymbol: false, currency: 'USD') : '',
    );
    _closingDayController = TextEditingController(text: acc.closingDay?.toString() ?? '');
    _paymentDueDayController = TextEditingController(text: acc.paymentDueDay?.toString() ?? '');
    _minPaymentCopController = TextEditingController(
      text: acc.minimumPaymentCop > 0
          ? CurrencyFormatter.format(acc.minimumPaymentCop, includeSymbol: false)
          : '',
    );
    _minPaymentUsdController = TextEditingController(
      text: acc.minimumPaymentUsd > 0
          ? CurrencyFormatter.format(acc.minimumPaymentUsd,
              includeSymbol: false, currency: 'USD')
          : '',
    );

    _selectedType = acc.type;
    _selectedIcon = acc.icon;

    // Investment fields — initialise from existing details if present
    final inv = acc.investmentDetails;
    _principalController = TextEditingController(
      text: inv?.principal != null
          ? CurrencyFormatter.format(inv!.principal!, includeSymbol: false)
          : '',
    );
    _interestRateController = TextEditingController(
      text: inv?.interestRate != null
          ? (inv!.interestRate! * 100).toStringAsFixed(2)
          : '',
    );
    _termDaysController =
        TextEditingController(text: inv?.termDays?.toString() ?? '');
    _fundCodeController = TextEditingController(text: inv?.fundCode ?? '');

    if (inv != null) {
      _selectedInvestmentType = inv.investmentType;
      _investmentBaseCurrency = inv.baseCurrency;
      _cdtStartDate = inv.startDate;
      _cdtMaturityDate = inv.maturityDate;
    }

    // Savings interest — initialise from existing savings_interest_details
    final sid = acc.interestDetails;
    _initialApyRate = sid?.apyRate;
    _apyRateController = TextEditingController(
      text: sid?.apyRate != null
          ? (sid!.apyRate! * 100).toStringAsFixed(2)
          : '',
    );
    _savingsInterestPeriod = sid?.interestPeriod ?? 'monthly';
    _savingsLastInterestDate = sid?.lastInterestDate;
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
    _minPaymentCopController.dispose();
    _minPaymentUsdController.dispose();
    _apyRateController.dispose();
    _principalController.dispose();
    _interestRateController.dispose();
    _termDaysController.dispose();
    _fundCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pendingIconBytes = bytes;
      _selectedIcon = null;
    });
  }

  Widget _buildIconPicker() {
    final theme = Theme.of(context);
    final hasImage = _pendingIconBytes != null;
    final hasUrl = _selectedIcon != null && _selectedIcon!.startsWith('http');

    Widget preview;
    if (hasImage) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_pendingIconBytes!, width: 48, height: 48, fit: BoxFit.cover),
      );
    } else if (hasUrl) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(_selectedIcon!, width: 48, height: 48, fit: BoxFit.cover),
      );
    } else {
      preview = Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.image_outlined, color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            preview,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasImage ? 'Image selected' : (hasUrl ? 'Custom icon' : 'No icon selected'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    'Optional — 256×256 image (JPG/PNG)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (hasImage || hasUrl)
              TextButton.icon(
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Remove'),
                onPressed: () => setState(() {
                  _pendingIconBytes = null;
                  _selectedIcon = null;
                }),
              ),
            TextButton.icon(
              onPressed: _pickIcon,
              icon: const Icon(Icons.upload, size: 18),
              label: Text(hasImage || hasUrl ? 'Change' : 'Choose'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _updateAccount() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    // Upload pending icon before building accountData so the URL is included.
    if (_pendingIconBytes != null) {
      try {
        final url = await ref
            .read(financeRepositoryProvider)
            .uploadAccountIcon(widget.account.id, _pendingIconBytes!);
        _selectedIcon = url;
        _pendingIconBytes = null;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Icon upload failed: $e')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
    }

    // For credit cards the user enters a positive debt amount; store as negative.
    final rawBalance = CurrencyFormatter.parse(_balanceController.text);
    final accountData = <String, dynamic>{
      'name': _nameController.text,
      'type': _selectedType,
      'balance': _selectedType == 'credit_card' ? -rawBalance : rawBalance,
      'icon': _selectedIcon,
    };

    if (_selectedType == 'credit_card') {
      accountData['credit_limit'] = _creditLimitController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_creditLimitController.text);
      accountData['balance_usd'] = _balanceUsdController.text.isEmpty
          ? 0.0
          : -(CurrencyFormatter.parse(_balanceUsdController.text, currency: 'USD'));
      accountData['credit_limit_usd'] = _creditLimitUsdController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_creditLimitUsdController.text, currency: 'USD');
      accountData['closing_day'] = _closingDayController.text.isEmpty
          ? null
          : int.parse(_closingDayController.text);
      accountData['payment_due_day'] = _paymentDueDayController.text.isEmpty
          ? null
          : int.parse(_paymentDueDayController.text);
      accountData['minimum_payment_cop'] = _minPaymentCopController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_minPaymentCopController.text);
      accountData['minimum_payment_usd'] = _minPaymentUsdController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_minPaymentUsdController.text,
              currency: 'USD');
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
        brokerId:
            _selectedBroker?.id ?? widget.account.investmentDetails?.brokerId,
        baseCurrency: _investmentBaseCurrency,
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
        initialBalance: widget.account.investmentDetails?.initialBalance,
      );
    } else {
      // Clear credit card specific fields if type changed
      accountData['credit_limit'] = 0.0;
      accountData['balance_usd'] = 0.0;
      accountData['credit_limit_usd'] = 0.0;
      accountData['closing_day'] = null;
      accountData['payment_due_day'] = null;
      accountData['minimum_payment_cop'] = 0.0;
      accountData['minimum_payment_usd'] = 0.0;
    }

    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.updateAccount(widget.account.id, accountData);

      // Savings APY — apply to type='savings' (parent or pocket).
      if (_selectedType == 'savings') {
        final newApyText = _apyRateController.text.trim();
        final newApy = newApyText.isEmpty
            ? null
            : (double.tryParse(newApyText) ?? 0) / 100;
        final existing = widget.account.interestDetails;

        if (existing == null && newApy != null && newApy > 0) {
          await repo.createSavingsInterestDetails(
            accountId: widget.account.id,
            apyRate: newApy,
            interestPeriod: _savingsInterestPeriod,
            lastInterestDate: _savingsLastInterestDate,
          );
        } else if (existing != null && newApy != null) {
          final changed = (_initialApyRate ?? -1) != newApy;
          if (changed) {
            await repo.updateSavingsApy(
              detailsId: existing.id,
              oldApyRate: _initialApyRate,
              oldBalance: widget.account.balance,
              lastInterestDate: existing.lastInterestDate,
              newApyRate: newApy,
              newInterestPeriod: _savingsInterestPeriod,
            );
          } else {
            // Period / last_interest_date patch without touching APY.
            await repo.rawUpdateSavingsInterestDetails(existing.id, {
              'interest_period': _savingsInterestPeriod,
              if (_savingsLastInterestDate != null)
                'last_interest_date':
                    '${_savingsLastInterestDate!.year}-${_savingsLastInterestDate!.month.toString().padLeft(2, '0')}-${_savingsLastInterestDate!.day.toString().padLeft(2, '0')}',
            });
          }
        }
      }

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

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    // Capture route/navigator/messenger before the async gap so we can use
    // them even after the dialog is popped or the widget is unmounted.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final currentPath = GoRouterState.of(context).uri.path;
    final onDetailRoute = currentPath.startsWith('/credit-card/') ||
        currentPath.startsWith('/investment/') ||
        currentPath.startsWith('/pockets/');

    try {
      await ref.read(financeRepositoryProvider).deleteAccount(widget.account.id);

      ref.invalidate(accountsProvider);
      ref.invalidate(recentTransactionsProvider); // Transactions might be gone

      navigator.pop();
      // If we were on a per-account detail route, the account no longer
      // exists — bail out to the accounts list instead of stranding the
      // user on a spinner.
      if (onDetailRoute) {
        router.go('/accounts');
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: kDialogPadding,
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
                      child: Text('Edit Account', style: Theme.of(context).textTheme.headlineSmall),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Account Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 10),

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
                const SizedBox(height: 10),

                // Balance
                TextFormField(
                  controller: _balanceController,
                  decoration: InputDecoration(
                    labelText: isCreditCard ? 'Current Debt (amount owed)' : 'Current Balance',
                    helperText: isCreditCard
                        ? 'Enter how much you currently owe on this card.'
                        : 'Adjust to reconcile with bank',
                    prefixText: '\$',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(
                      decimal: true, signed: !isCreditCard),
                  inputFormatters: [const CurrencyInputFormatter()],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (CurrencyFormatter.parse(value) == 0.0 && value != '0' && value != '0.0') return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Icon picker
                _buildIconPicker(),
                const SizedBox(height: 10),

                // Savings APY block (applies to type=savings: parent or pocket)
                if (_selectedType == 'savings') ...[
                  const Divider(),
                  Text('Interest (optional)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _apyRateController,
                          decoration: const InputDecoration(
                            labelText: 'APY (E.A. %)',
                            suffixText: '%',
                            border: OutlineInputBorder(),
                            hintText: 'e.g. 9.25',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _savingsInterestPeriod,
                          decoration: const InputDecoration(
                            labelText: 'Period',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'monthly', child: Text('Monthly')),
                            DropdownMenuItem(
                                value: 'daily', child: Text('Daily')),
                            DropdownMenuItem(
                                value: 'on_withdrawal',
                                child: Text('On withdrawal')),
                          ],
                          onChanged: (v) =>
                              setState(() => _savingsInterestPeriod = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _savingsLastInterestDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _savingsLastInterestDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Last interest recorded',
                        border: const OutlineInputBorder(),
                        suffixIcon: _savingsLastInterestDate != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(
                                    () => _savingsLastInterestDate = null),
                              )
                            : const Icon(Icons.calendar_today, size: 18),
                        helperText:
                            'APY changes automatically close the current interest segment with the old rate before applying the new one.',
                      ),
                      child: Text(
                        _savingsLastInterestDate != null
                            ? DateFormat('MMM d, y')
                                .format(_savingsLastInterestDate!)
                            : 'Not set',
                        style: _savingsLastInterestDate == null
                            ? Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.45))
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Credit Card specific fields
                if (isCreditCard) ...[
                  const Divider(),
                  Text('Credit Card Details', 
                    style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),

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
                  const SizedBox(height: 10),

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
                      labelText: 'Current USD Debt',
                      prefixText: 'US\$',
                      border: OutlineInputBorder(),
                      helperText: 'Leave empty if no USD balance.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                  const SizedBox(height: 10),

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
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _minPaymentCopController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum Payment (COP)',
                            prefixText: '\$',
                            border: OutlineInputBorder(),
                            helperText: 'From your statement.',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [const CurrencyInputFormatter()],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _minPaymentUsdController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum Payment (USD)',
                            prefixText: 'US\$',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            const CurrencyInputFormatter(currency: 'USD')
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Investment section ────────────────────────────────────
                if (isInvestment) ...[
                  const Divider(),
                  Text('Investment Details',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),

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

                  if (_selectedInvestmentType == InvestmentType.stockEtf ||
                      _selectedInvestmentType == InvestmentType.crypto) ...[
                    DropdownButtonFormField<String>(
                      value: _investmentBaseCurrency,
                      decoration: const InputDecoration(
                        labelText: 'Cash Currency',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'COP', child: Text('COP')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                      ],
                      onChanged: (v) =>
                          setState(() => _investmentBaseCurrency = v!),
                    ),
                    const SizedBox(height: 12),
                  ],

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

                const SizedBox(height: 16),

                // Actions
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading ? null : _deleteAccount,
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
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
