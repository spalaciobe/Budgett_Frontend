import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/repositories/bank_repository.dart';
import '../../data/repositories/broker_repository.dart';
import '../../data/models/bank_model.dart';
import '../../data/models/broker_model.dart';
import '../../data/models/investment_details_model.dart';

/// Builds the credit-card rules map for a given bank.
/// Shared logic used both in [AddAccountDialog] and the onboarding flow.
Map<String, dynamic> buildCreditCardRulesForBank({
  required Bank bank,
  int? cutoffDay,
  int? paymentDay,
}) {
  switch (bank.code) {
    case 'RAPPICARD':
      // RappiCard: relative cutoff (penultimate business day), payment 10 calendar days later.
      return {
        'banco_id': bank.id,
        'tipo_corte': 'relativo',
        'corte_relativo_tipo': 'penultimo_dia_habil',
        'tipo_pago': 'relativo_dias',
        'dias_despues_corte': 10,
        'tipo_offset_pago': 'calendario',
      };

    case 'NUBANK':
      // Nubank: fixed cutoff, payment in next month on a business day.
      return {
        'banco_id': bank.id,
        'tipo_corte': 'fijo',
        'dia_corte_nominal': cutoffDay ?? 25,
        'tipo_pago': 'fijo',
        'dia_pago_nominal': paymentDay ?? 7,
        'mes_pago': 'siguiente',
        'tipo_offset_pago': 'habiles',
      };

    case 'BANCOLOMBIA':
    case 'DAVIVIENDA':
    case 'BBVA':
    default:
      // Most Colombian banks: fixed cutoff & payment, calendar offset.
      return {
        'banco_id': bank.id,
        'tipo_corte': 'fijo',
        'dia_corte_nominal': cutoffDay ?? 15,
        'tipo_pago': 'fijo',
        'dia_pago_nominal': paymentDay ?? 30,
        'mes_pago': 'siguiente',
        'tipo_offset_pago': 'calendario',
      };
  }
}

/// Builds the investment_details map for a given investment configuration.
/// Shared logic used both in [AddAccountDialog] and [EditAccountDialog].
Map<String, dynamic> buildInvestmentDetailsMap({
  required InvestmentType investmentType,
  String? brokerId,
  String baseCurrency = 'COP',
  double? principal,
  double? interestRate,
  int? termDays,
  DateTime? startDate,
  DateTime? maturityDate,
  bool autoRenew = false,
  String? fundCode,
  double? initialBalance,
}) {
  String? startDateStr;
  String? maturityDateStr;
  if (startDate != null) {
    startDateStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
  }
  if (maturityDate != null) {
    maturityDateStr =
        '${maturityDate.year}-${maturityDate.month.toString().padLeft(2, '0')}-${maturityDate.day.toString().padLeft(2, '0')}';
  }

  return {
    'investment_type': investmentType.toDbString(),
    'broker_id': brokerId,
    'base_currency': baseCurrency,
    'principal': investmentType == InvestmentType.cdt ? principal : null,
    'interest_rate': investmentType == InvestmentType.cdt ? interestRate : null,
    'term_days': investmentType == InvestmentType.cdt ? termDays : null,
    'start_date': investmentType == InvestmentType.cdt ? startDateStr : null,
    'maturity_date': investmentType == InvestmentType.cdt ? maturityDateStr : null,
    'auto_renew': investmentType == InvestmentType.cdt ? autoRenew : false,
    'fund_code': investmentType == InvestmentType.fic ? fundCode : null,
    'nav_currency': investmentType == InvestmentType.fic ? baseCurrency : null,
    'initial_balance': initialBalance,
  };
}

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
  final _balanceUsdController = TextEditingController();
  final _creditLimitUsdController = TextEditingController();
  final _cutoffDayController = TextEditingController();
  final _paymentDayController = TextEditingController();

  // Investment controllers
  final _principalController = TextEditingController();
  final _interestRateController = TextEditingController();
  final _termDaysController = TextEditingController();
  final _fundCodeController = TextEditingController();
  DateTime? _cdtStartDate;
  DateTime? _cdtMaturityDate;

  String _selectedType = 'checking';
  String? _selectedIcon;
  Uint8List? _pendingIconBytes;
  bool _isLoading = false;
  Bank? _selectedBank;
  // Bancolombia/Davivienda/BBVA have two well-known billing cycles
  int? _selectedCycle; // 15 or 30 — null until user picks

  // Investment fields
  InvestmentType _selectedInvestmentType = InvestmentType.cdt;
  String _investmentBaseCurrency = 'COP';
  Broker? _selectedBroker;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    _balanceUsdController.dispose();
    _creditLimitUsdController.dispose();
    _cutoffDayController.dispose();
    _paymentDayController.dispose();
    _principalController.dispose();
    _interestRateController.dispose();
    _termDaysController.dispose();
    _fundCodeController.dispose();
    super.dispose();
  }

  /// True if the selected bank has automatic (non-configurable) rules.
  bool get _bankHasAutoRules =>
      _selectedBank != null && _selectedBank!.code == 'RAPPICARD';

  /// True if the user needs to enter cutoff/payment days.
  bool get _needsManualDays =>
      _selectedType == 'credit_card' &&
      _selectedBank != null &&
      !_bankHasAutoRules;

  /// True if this bank uses well-known billing cycles (Ciclo 15 / Ciclo 30).
  bool get _bankHasCycles =>
      _selectedBank != null &&
      ['BANCOLOMBIA', 'DAVIVIENDA', 'BBVA'].contains(_selectedBank!.code);

  /// Pre-fill default days when the bank is selected.
  void _onBankSelected(Bank? bank) {
    setState(() {
      _selectedBank = bank;
      _selectedCycle = null;
      _cutoffDayController.clear();
      _paymentDayController.clear();
      if (bank == null) return;

      switch (bank.code) {
        case 'NUBANK':
          _cutoffDayController.text = '25';
          _paymentDayController.text = '7';
          break;
        // BANCOLOMBIA / DAVIVIENDA / BBVA: wait for cycle selection
        case 'BANCOLOMBIA':
        case 'DAVIVIENDA':
        case 'BBVA':
          break;
        default:
          // Unknown bank — leave fields empty for manual entry
          break;
      }
    });
  }

  void _onCycleSelected(int cycle) {
    setState(() {
      _selectedCycle = cycle;
      _cutoffDayController.text = cycle.toString();
      // Correct payment days per Bancolombia 2026 data:
      // Ciclo 15 → day 2 of next month
      // Ciclo 30 → day 16 of next month
      _paymentDayController.text = cycle == 15 ? '2' : '16';
    });
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

  void _autoComputeMaturity() {
    final start = _cdtStartDate;
    final days = int.tryParse(_termDaysController.text);
    if (start != null && days != null) {
      setState(() => _cdtMaturityDate = start.add(Duration(days: days)));
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final accountData = <String, dynamic>{
      'name': _nameController.text.trim(),
      'type': _selectedType,
      'balance': CurrencyFormatter.parse(_balanceController.text),
      'icon': _selectedIcon,
    };

    if (_selectedType == 'credit_card') {
      // User enters debt as a positive amount — store it as negative.
      accountData['balance'] = -(CurrencyFormatter.parse(_balanceController.text));
      accountData['credit_limit'] = _creditLimitController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_creditLimitController.text);
      accountData['balance_usd'] = _balanceUsdController.text.isEmpty
          ? 0.0
          : -(CurrencyFormatter.parse(_balanceUsdController.text, currency: 'USD'));
      accountData['credit_limit_usd'] = _creditLimitUsdController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_creditLimitUsdController.text, currency: 'USD');

      if (_selectedBank != null) {
        final cutoffDay = int.tryParse(_cutoffDayController.text);
        final paymentDay = int.tryParse(_paymentDayController.text);

        accountData['credit_card_details'] = buildCreditCardRulesForBank(
          bank: _selectedBank!,
          cutoffDay: cutoffDay,
          paymentDay: paymentDay,
        );
      }
    } else if (_selectedType == 'investment') {
      final principalValue = _principalController.text.isEmpty
          ? null
          : CurrencyFormatter.parse(_principalController.text);
      final balanceInBase = _balanceController.text.isEmpty
          ? null
          : CurrencyFormatter.parse(
              _balanceController.text,
              currency: _investmentBaseCurrency,
            );
      // CDTs lock their seed inside `principal`; multi-holding accounts hold
      // it as cash in the base currency. Either way, it's the user's initial
      // commitment and should count toward Funded.
      final initialBalance = _selectedInvestmentType == InvestmentType.cdt
          ? principalValue
          : balanceInBase;

      accountData['investment_details'] = buildInvestmentDetailsMap(
        investmentType: _selectedInvestmentType,
        brokerId: _selectedBroker?.id,
        baseCurrency: _investmentBaseCurrency,
        principal: principalValue,
        interestRate: double.tryParse(_interestRateController.text) != null
            ? double.parse(_interestRateController.text) / 100
            : null,
        termDays: int.tryParse(_termDaysController.text),
        startDate: _cdtStartDate,
        maturityDate: _cdtMaturityDate,
        fundCode: _fundCodeController.text.trim().isEmpty
            ? null
            : _fundCodeController.text.trim(),
        initialBalance: initialBalance,
      );
      if (_investmentBaseCurrency == 'USD') {
        accountData['balance_usd'] = CurrencyFormatter.parse(
          _balanceController.text,
          currency: 'USD',
        );
        accountData['balance'] = 0.0;
      }
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      final accountId = await repo.createAccount(accountData);

      if (_pendingIconBytes != null) {
        final url = await repo.uploadAccountIcon(accountId, _pendingIconBytes!);
        await repo.updateAccount(accountId, {'icon': url});
      }

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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    return Row(
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
        if (hasImage || hasUrl)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove icon',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCreditCard = _selectedType == 'credit_card';
    final isInvestment = _selectedType == 'investment';
    final banksAsync = ref.watch(banksFutureProvider);
    final brokersAsync = ref.watch(brokersFutureProvider);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
        padding: kDialogPadding,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text('Add Account',
                          style: Theme.of(context).textTheme.headlineSmall),
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
                    hintText: 'e.g. Bancolombia Savings, Nubank CC',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),

                // Type
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Account Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'checking',
                        child: Text('Checking Account')),
                    DropdownMenuItem(
                        value: 'savings',
                        child: Text('Savings Account')),
                    DropdownMenuItem(
                        value: 'credit_card',
                        child: Text('Credit Card')),
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(
                        value: 'investment',
                        child: Text('Investment')),
                  ],
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
                const SizedBox(height: 10),

                // Balance
                TextFormField(
                  controller: _balanceController,
                  decoration: InputDecoration(
                    labelText: isCreditCard
                        ? 'Current Debt (amount owed)'
                        : isInvestment
                            ? 'Cash Balance (uninvested)'
                            : 'Initial Balance',
                    prefixText: isInvestment && _investmentBaseCurrency == 'USD'
                        ? 'US\$'
                        : '\$',
                    border: const OutlineInputBorder(),
                    helperText: isCreditCard
                        ? 'Enter how much you currently owe on this card.'
                        : null,
                  ),
                  keyboardType: TextInputType.numberWithOptions(
                      decimal: true, signed: !isCreditCard),
                  inputFormatters: [
                    CurrencyInputFormatter(
                      currency: isInvestment && _investmentBaseCurrency == 'USD'
                          ? 'USD'
                          : 'COP',
                    ),
                  ],
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),

                // Icon picker
                _buildIconPicker(),

                // ── Credit card section ───────────────────────────────────
                if (isCreditCard) ...[
                  const SizedBox(height: 10),
                  const Divider(),
                  Text('Card Details',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),

                  // Bank selector
                  banksAsync.when(
                    data: (banks) => DropdownButtonFormField<Bank>(
                      value: _selectedBank,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Issuing Bank',
                        border: OutlineInputBorder(),
                      ),
                      items: banks
                          .map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(
                                  b.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: _onBankSelected,
                      validator: (v) =>
                          v == null ? 'Select a bank' : null,
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error loading banks: $e'),
                  ),
                  const SizedBox(height: 10),

                  // Credit limit
                  TextFormField(
                    controller: _creditLimitController,
                    decoration: const InputDecoration(
                      labelText: 'Total Credit Limit (COP)',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [const CurrencyInputFormatter()],
                  ),
                  const SizedBox(height: 10),

                  // USD slice (optional)
                  const Divider(),
                  Text('USD Balance (optional)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 4),
                  Text(
                    'If your card has a USD balance, enter it here.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                  ),
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
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [const CurrencyInputFormatter(currency: 'USD')],
                  ),

                  // RappiCard: auto-rules notice
                  if (_bankHasAutoRules) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF441A).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                const Color(0xFFFF441A).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: Color(0xFFFF441A), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'RappiCard: statement on the second-to-last business day of the month, payment 10 days later. Automatic configuration.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Cycle selector for banks with well-known cycles (Bancolombia, Davivienda, BBVA)
                  if (_needsManualDays && _bankHasCycles) ...[
                    const SizedBox(height: 10),
                    Text('Billing Cycle',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 15, label: Text('Cycle 15'), icon: Icon(Icons.looks_one_outlined, size: 16)),
                        ButtonSegment(value: 30, label: Text('Cycle 30'), icon: Icon(Icons.looks_two_outlined, size: 16)),
                      ],
                      selected: _selectedCycle != null ? {_selectedCycle!} : {},
                      emptySelectionAllowed: true,
                      onSelectionChanged: (s) {
                        if (s.isNotEmpty) _onCycleSelected(s.first);
                      },
                    ),
                    if (_selectedCycle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _selectedCycle == 15
                            ? 'Statement on the 15th, payment on the 2nd of next month'
                            : 'Statement on the 30th, payment on the 16th of next month',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ],

                  // Manual cutoff/payment days (non-Rappi)
                  if (_needsManualDays) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cutoffDayController,
                            decoration: const InputDecoration(
                              labelText: 'Statement Day',
                              border: OutlineInputBorder(),
                              hintText: '1–31',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _paymentDayController,
                            decoration: const InputDecoration(
                              labelText: 'Payment Day',
                              border: OutlineInputBorder(),
                              hintText: '1–31',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    if (_selectedBank != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Holidays and weekends are automatically adjusted according to ${_selectedBank!.name} rules.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.55),
                                ),
                      ),
                    ],
                  ],
                ],

                // ── Investment section ────────────────────────────────────
                if (isInvestment) ...[
                  const SizedBox(height: 10),
                  const Divider(),
                  Text('Investment Details',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),

                  // Investment type
                  DropdownButtonFormField<InvestmentType>(
                    value: _selectedInvestmentType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Investment Type',
                      border: OutlineInputBorder(),
                    ),
                    items: InvestmentType.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                t.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedInvestmentType = v!;
                      _selectedBroker = null;
                      // Default currency
                      _investmentBaseCurrency =
                          (v == InvestmentType.stockEtf) ? 'USD' : 'COP';
                    }),
                  ),
                  const SizedBox(height: 10),

                  // Base currency (only for stock_etf / crypto)
                  if (_selectedInvestmentType == InvestmentType.stockEtf ||
                      _selectedInvestmentType == InvestmentType.crypto) ...[
                    DropdownButtonFormField<String>(
                      value: _investmentBaseCurrency,
                      isExpanded: true,
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
                    const SizedBox(height: 10),
                  ],

                  // Broker
                  brokersAsync.when(
                    data: (brokers) {
                      final filtered = brokers
                          .where((b) => b.supportedTypes
                              .contains(_selectedInvestmentType.toDbString()))
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
                    loading: () => const Center(
                        child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Text('Error loading brokers: $e'),
                  ),
                  const SizedBox(height: 10),

                  // ── CDT fields ─────────────────────────────────────────
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
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _interestRateController,
                            decoration: const InputDecoration(
                              labelText: 'Annual Rate (E.A. %)',
                              suffixText: '%',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
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
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                            onChanged: (_) => _autoComputeMaturity(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Start date
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _cdtStartDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                        );
                        if (picked != null) {
                          setState(() {
                            _cdtStartDate = picked;
                            _autoComputeMaturity();
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Start Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(
                          _cdtStartDate != null
                              ? '${_cdtStartDate!.year}-${_cdtStartDate!.month.toString().padLeft(2, '0')}-${_cdtStartDate!.day.toString().padLeft(2, '0')}'
                              : 'Select date',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Maturity date (auto or manual)
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _cdtMaturityDate ?? DateTime.now().add(const Duration(days: 180)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                        );
                        if (picked != null) {
                          setState(() => _cdtMaturityDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Maturity Date (auto-computed)',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.event_available, size: 18),
                        ),
                        child: Text(
                          _cdtMaturityDate != null
                              ? '${_cdtMaturityDate!.year}-${_cdtMaturityDate!.month.toString().padLeft(2, '0')}-${_cdtMaturityDate!.day.toString().padLeft(2, '0')}'
                              : 'Auto-computed from start + term',
                        ),
                      ),
                    ),
                  ],

                  // ── FIC fields ─────────────────────────────────────────
                  if (_selectedInvestmentType == InvestmentType.fic) ...[
                    TextFormField(
                      controller: _fundCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Fund Code (optional)',
                        border: OutlineInputBorder(),
                        hintText: 'e.g. TYBA-RF',
                      ),
                    ),
                  ],

                  // ── Multi-holding info banner ───────────────────────────
                  if (_selectedInvestmentType.isMultiHolding) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color:
                                Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Add your positions (holdings) from the account detail screen after creating the account.',
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 16),

                // Save
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _saveAccount,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create Account'),
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
