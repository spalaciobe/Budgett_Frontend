import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_spacing.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

enum _PaymentPreset { minimum, currentBalance, custom }

class PayCreditCardDialog extends ConsumerStatefulWidget {
  final Account card;

  const PayCreditCardDialog({super.key, required this.card});

  @override
  ConsumerState<PayCreditCardDialog> createState() =>
      _PayCreditCardDialogState();
}

class _PayCreditCardDialogState extends ConsumerState<PayCreditCardDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _settleController;
  late TextEditingController _debitController;
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _sourceAccountId;
  _PaymentPreset _preset = _PaymentPreset.currentBalance;
  final Set<String> _closedInstallments = {};
  bool _saving = false;

  late final String _debtCurrency = _pickInitialDebtCurrency();

  String _pickInitialDebtCurrency() {
    final cop = widget.card.balance.abs();
    final usd = widget.card.balanceUsd.abs();
    if (usd > 0 && cop == 0) return 'USD';
    if (cop > 0 && usd == 0) return 'COP';
    return cop >= usd ? 'COP' : 'USD';
  }

  double get _cardDebt =>
      _debtCurrency == 'USD' ? widget.card.balanceUsd.abs() : widget.card.balance.abs();

  double get _cardMinimum => _debtCurrency == 'USD'
      ? widget.card.minimumPaymentUsd
      : widget.card.minimumPaymentCop;

  Account? get _sourceAccount {
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    if (_sourceAccountId == null) return null;
    try {
      return accounts.firstWhere((a) => a.id == _sourceAccountId);
    } catch (_) {
      return null;
    }
  }

  String get _sourceCurrency {
    final src = _sourceAccount;
    if (src == null) return 'COP';
    // A savings/checking account with both balances — prefer COP unless only USD has funds.
    if (src.balance > 0) return 'COP';
    if (src.balanceUsd > 0) return 'USD';
    return 'COP';
  }

  bool get _crossCurrency => _debtCurrency != _sourceCurrency;

  @override
  void initState() {
    super.initState();
    _settleController = TextEditingController();
    _debitController = TextEditingController();
    _applyPreset(_PaymentPreset.currentBalance);
  }

  @override
  void dispose() {
    _settleController.dispose();
    _debitController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _applyPreset(_PaymentPreset preset) {
    setState(() {
      _preset = preset;
      if (preset == _PaymentPreset.minimum) {
        _closedInstallments.clear();
        _setSettle(_cardMinimum);
      } else if (preset == _PaymentPreset.currentBalance) {
        _setSettle(_cardDebt + _closedInstallmentsTotal());
      } else {
        // custom — leave whatever is in the field
      }
    });
  }

  void _setSettle(double amount) {
    _settleController.text = amount <= 0
        ? ''
        : CurrencyFormatter.format(
            amount,
            includeSymbol: false,
            currency: _debtCurrency,
          );
    if (!_crossCurrency) {
      _debitController.text = _settleController.text;
    }
  }

  double _closedInstallmentsTotal() {
    final txs = ref.read(accountDetailTransactionsProvider(widget.card.id)).valueOrNull ?? [];
    return txs
        .where((t) => _closedInstallments.contains(t.id))
        .fold<double>(0.0, (s, t) => s + t.amount);
  }

  List<Transaction> _pendingInstallments(List<Transaction> txs) {
    return txs
        .where((t) =>
            t.parentTransactionId != null &&
            t.status == 'pending' &&
            t.accountId == widget.card.id)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_sourceAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a source account')),
      );
      return;
    }

    final settle = CurrencyFormatter.parse(
      _settleController.text,
      currency: _debtCurrency,
    );
    final debit = _crossCurrency
        ? CurrencyFormatter.parse(
            _debitController.text,
            currency: _sourceCurrency,
          )
        : settle;

    if (settle <= 0 || debit <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amounts must be greater than 0')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.payCreditCard(
        sourceAccountId: _sourceAccountId!,
        cardAccountId: widget.card.id,
        settleAmount: settle,
        debtCurrency: _debtCurrency,
        debitAmount: debit,
        sourceCurrency: _sourceCurrency,
        date: _selectedDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        closedInstallmentIds: _closedInstallments.toList(),
      );

      ref.invalidate(accountsProvider);
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountDetailTransactionsProvider(widget.card.id));

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment posted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final sources = accounts
        .where((a) => a.type != 'credit_card' && (a.balance > 0 || a.balanceUsd > 0))
        .toList();

    final installmentsAsync = ref.watch(accountDetailTransactionsProvider(widget.card.id));
    final pending = installmentsAsync.valueOrNull == null
        ? <Transaction>[]
        : _pendingInstallments(installmentsAsync.value!);

    return AlertDialog(
      title: Text('Pay ${widget.card.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Current debt: ${CurrencyFormatter.format(_cardDebt, currency: _debtCurrency)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                kGapLg,
                DropdownButtonFormField<String>(
                  value: _sourceAccountId,
                  decoration: const InputDecoration(labelText: 'Pay from'),
                  items: sources
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              '${a.name} · ${CurrencyFormatter.format(a.balance > 0 ? a.balance : a.balanceUsd, currency: a.balance > 0 ? 'COP' : 'USD')}',
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _sourceAccountId = v;
                    // Re-apply preset so Settle/Debit fields stay in sync when currencies change.
                    _applyPreset(_preset);
                  }),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                kGapLg,
                Wrap(
                  spacing: kSpaceLg,
                  children: [
                    ChoiceChip(
                      label: Text(_cardMinimum > 0
                          ? 'Minimum (${CurrencyFormatter.format(_cardMinimum, currency: _debtCurrency)})'
                          : 'Minimum (not set)'),
                      selected: _preset == _PaymentPreset.minimum,
                      onSelected: _cardMinimum <= 0
                          ? null
                          : (_) => _applyPreset(_PaymentPreset.minimum),
                    ),
                    ChoiceChip(
                      label: const Text('Current balance'),
                      selected: _preset == _PaymentPreset.currentBalance,
                      onSelected: (_) => _applyPreset(_PaymentPreset.currentBalance),
                    ),
                    ChoiceChip(
                      label: const Text('Custom'),
                      selected: _preset == _PaymentPreset.custom,
                      onSelected: (_) => _applyPreset(_PaymentPreset.custom),
                    ),
                  ],
                ),
                kGapLg,
                TextFormField(
                  controller: _settleController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter(currency: _debtCurrency)],
                  readOnly: _preset != _PaymentPreset.custom,
                  decoration: InputDecoration(
                    labelText: 'Settle on card',
                    prefixText: CurrencyFormatter.prefixFor(_debtCurrency),
                    helperText:
                        'Amount subtracted from the card debt (in $_debtCurrency).',
                  ),
                  onChanged: (_) {
                    if (!_crossCurrency) {
                      _debitController.text = _settleController.text;
                    }
                  },
                ),
                if (_crossCurrency) ...[
                  kGapLg,
                  TextFormField(
                    controller: _debitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [CurrencyInputFormatter(currency: _sourceCurrency)],
                    decoration: InputDecoration(
                      labelText: 'Debit from source',
                      prefixText: CurrencyFormatter.prefixFor(_sourceCurrency),
                      helperText:
                          'What your bank actually charges in $_sourceCurrency (the rate is derived from both amounts).',
                    ),
                  ),
                ],
                if (pending.isNotEmpty &&
                    _preset == _PaymentPreset.currentBalance) ...[
                  kGapXl,
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      'Close pending installments (${_closedInstallments.length}/${pending.length})',
                    ),
                    subtitle: const Text(
                      'Checked ones are marked paid today and added to the settle amount.',
                    ),
                    children: pending.map((t) {
                      final checked = _closedInstallments.contains(t.id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${t.description} · ${t.installmentNumber ?? '?'}/${t.numCuotas ?? '?'}',
                        ),
                        subtitle: Text(
                          '${CurrencyFormatter.format(t.amount, currency: t.currency)} · due ${DateFormat.yMMMd().format(t.date)}',
                        ),
                        value: checked,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _closedInstallments.add(t.id);
                          } else {
                            _closedInstallments.remove(t.id);
                          }
                          _applyPreset(_PaymentPreset.currentBalance);
                        }),
                      );
                    }).toList(),
                  ),
                ],
                kGapLg,
                Row(
                  children: [
                    Expanded(
                      child: Text('Date: ${DateFormat.yMMMd().format(_selectedDate)}'),
                    ),
                    TextButton(onPressed: _pickDate, child: const Text('Change')),
                  ],
                ),
                kGapLg,
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Pay'),
        ),
      ],
    );
  }
}
