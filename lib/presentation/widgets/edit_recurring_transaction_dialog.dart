import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

class EditRecurringTransactionDialog extends ConsumerStatefulWidget {
  final RecurringTransaction transaction;

  const EditRecurringTransactionDialog({super.key, required this.transaction});

  @override
  ConsumerState<EditRecurringTransactionDialog> createState() =>
      _EditRecurringTransactionDialogState();
}

class _EditRecurringTransactionDialogState
    extends ConsumerState<EditRecurringTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;

  late String _type;
  late String _frequency;
  late String _currency;
  late bool _isActive;
  late DateTime _nextRunDate;
  String? _accountId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _descriptionController = TextEditingController(text: t.description);
    _amountController = TextEditingController(text: t.amount.toStringAsFixed(0));
    _type = t.type;
    _frequency = t.frequency;
    _currency = t.currency;
    _isActive = t.isActive;
    _nextRunDate = t.nextRunDate;
    _accountId = t.accountId;
    _categoryId = t.categoryId;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  List<Account> _flattenAccounts(List<Account> accounts) {
    final out = <Account>[];
    for (final a in accounts) {
      out.add(a);
      out.addAll(a.pockets);
    }
    return out;
  }

  List<DropdownMenuItem<String>> _buildAccountItems(List<Account> accounts) {
    final items = <DropdownMenuItem<String>>[];
    for (final a in accounts) {
      items.add(DropdownMenuItem(
        value: a.id,
        child: Text(
          a.name,
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ));
      for (final p in a.pockets) {
        items.add(DropdownMenuItem(
          value: p.id,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.subdirectory_arrow_right,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  p.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ));
      }
    }
    return items;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextRunDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) {
      setState(() => _nextRunDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null) return;

    final repo = ref.read(financeRepositoryProvider);
    await repo.updateRecurringTransaction(widget.transaction.id, {
      'description': _descriptionController.text.trim(),
      'amount': amount,
      'category_id': _categoryId,
      'account_id': _accountId,
      'type': _type,
      'frequency': _frequency,
      'next_run_date': _nextRunDate.toIso8601String().split('T')[0],
      'is_active': _isActive,
      'currency': _currency,
    });

    ref.invalidate(recurringTransactionsProvider);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return AlertDialog(
      title: const Text('Edit Recurring Transaction'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
                    ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.arrow_downward)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                kGapMd,
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                kGapMd,
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final parsed = double.tryParse((v ?? '').replaceAll(',', '.'));
                          if (parsed == null || parsed <= 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _currency,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'COP', child: Text('COP')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                        ],
                        onChanged: (v) => setState(() => _currency = v!),
                      ),
                    ),
                  ],
                ),
                kGapMd,
                DropdownButtonFormField<String>(
                  value: _frequency,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Frequency',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'biweekly', child: Text('Biweekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (v) => setState(() => _frequency = v!),
                ),
                kGapMd,
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Next Run Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(DateFormat('MM/dd/yyyy').format(_nextRunDate)),
                  ),
                ),
                kGapMd,
                accountsAsync.when(
                  data: (accounts) {
                    final flat = _flattenAccounts(accounts);
                    final valid = flat.any((a) => a.id == _accountId);
                    return DropdownButtonFormField<String>(
                      value: valid ? _accountId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        border: OutlineInputBorder(),
                      ),
                      items: _buildAccountItems(accounts),
                      onChanged: (v) => setState(() => _accountId = v),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Accounts error: $e'),
                ),
                kGapMd,
                categoriesAsync.when(
                  data: (categories) {
                    final filtered = categories
                        .where((c) => _type == 'income' ? c.isIncome : !c.isIncome)
                        .toList();
                    final valid = filtered.any((c) => c.id == _categoryId);
                    return DropdownButtonFormField<String?>(
                      value: valid ? _categoryId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category (optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ...filtered.map((c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(
                                c.name,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Categories error: $e'),
                ),
                kGapMd,
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Paused rules do not auto-generate transactions'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
