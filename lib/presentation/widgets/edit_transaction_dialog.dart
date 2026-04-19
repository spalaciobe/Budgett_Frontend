import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';
import 'package:budgett_frontend/core/utils/credit_card_calculator.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/widgets/credit_card_billing_simulator.dart';

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
  String? _fundedByCategoryId; // Model B: expense paid out of a sinking fund
  String? _savingsContributionCategoryId; // Model B: transfer tagged as fund contribution
  late String _status;
  late String _currency;
  bool _isUsdPayment = false;
  late TextEditingController _fxRateController;

  bool _isLoading = false;

  // Installment state (populated when editing an installment parent)
  int _numCuotas = 12;
  bool _interestFree = true;
  late TextEditingController _interestRateController;
  static const _cuotasOptions = [2, 3, 6, 9, 12, 18, 24, 36, 48];

  // Recurrence state (user can promote this transaction to a recurring one)
  bool _isRecurring = false;
  String _frequency = 'monthly';

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
    _fundedByCategoryId = t.fundedByCategoryId;
    // For a transfer that already carries a category_id, treat it as the
    // savings-fund contribution (transfers don't have any other category UX).
    _savingsContributionCategoryId =
        t.type == 'transfer' ? t.categoryId : null;
    _status = t.status;
    _isUsdPayment = t.isCrossCurrencyPayment;

    // Installment parent: restore installment config state
    if (t.isInstallmentParent) {
      _numCuotas = t.numCuotas ?? 12;
      _interestFree = !(t.hasInterest ?? false);
      final ratePercent = (t.interestRate ?? 0.0) * 100;
      _interestRateController = TextEditingController(
          text: ratePercent > 0 ? ratePercent.toStringAsFixed(3) : '');
    } else {
      _interestRateController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _fxRateController.dispose();
    _interestRateController.dispose();
    super.dispose();
  }

  /// Flattens the parent/pocket tree so pockets are selectable alongside
  /// top-level accounts.
  List<Account> _flattenAccounts(List<Account> accounts) {
    final out = <Account>[];
    for (final a in accounts) {
      out.add(a);
      out.addAll(a.pockets);
    }
    return out;
  }

  /// Builds dropdown items with pockets indented under their parent.
  List<DropdownMenuItem<String>> _buildAccountItems(
    List<Account> accounts, {
    String? excludeId,
  }) {
    final items = <DropdownMenuItem<String>>[];
    for (final a in accounts) {
      if (a.id != excludeId) {
        items.add(DropdownMenuItem(
          value: a.id,
          child: Text(a.name, style: const TextStyle(fontSize: 13)),
        ));
      }
      for (final p in a.pockets) {
        if (p.id == excludeId) continue;
        items.add(DropdownMenuItem(
          value: p.id,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.subdirectory_arrow_right,
                  size: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(p.name, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ));
      }
    }
    return items;
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
      'movement_type': null,
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
      final account = _flattenAccounts(accounts).firstWhereOrNull((a) => a.id == _selectedAccountId);
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

    // Sinking-fund linkage (Model B). Always emit the field so unsetting works.
    transactionData['funded_by_category_id'] =
        _selectedType == 'expense' ? _fundedByCategoryId : null;
    if (_selectedType == 'transfer') {
      transactionData['category_id'] = _savingsContributionCategoryId;
      transactionData['movement_type'] =
          _savingsContributionCategoryId != null ? 'savings' : null;
    }

    try {
      final repo = ref.read(financeRepositoryProvider);

      if (widget.transaction.isInstallmentParent) {
        // Installment parent: regenerate schedule.
        final accounts = ref.read(accountsProvider).valueOrNull ?? [];
        final account = _flattenAccounts(accounts)
            .firstWhereOrNull((a) => a.id == _selectedAccountId);
        if (account?.creditCardRules == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('This card has no billing rules configured.')),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
        final bank = await ref.read(bankRepositoryProvider).getBanks().then(
              (banks) => banks.firstWhereOrNull(
                  (b) => b.id == account!.creditCardRules!.bankId),
            );
        if (bank == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Could not load bank rules.')),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
        final rate = _interestFree
            ? 0.0
            : (double.tryParse(
                        _interestRateController.text.replaceAll(',', '')) ??
                    0.0) /
                100.0;
        final String? finalCategoryId = transactionData['category_id'] as String?;
        final String? finalSubCategoryId =
            transactionData['sub_category_id'] as String?;

        await repo.updateInstallmentPurchase(
          parentId: widget.transaction.id,
          accountId: _selectedAccountId!,
          amount: CurrencyFormatter.parse(_amountController.text,
              currency: _currency),
          numCuotas: _numCuotas,
          hasInterest: !_interestFree,
          interestRate: rate,
          purchaseDate: _selectedDate,
          currency: _currency,
          description: _descriptionController.text,
          rules: account!.creditCardRules!,
          bank: bank,
          categoryId: finalCategoryId,
          subCategoryId: finalSubCategoryId,
          expenseGroupId: null,
          notes: _notesController.text.isNotEmpty ? _notesController.text : null,
          movementType: null,
          status: _status,
        );
      } else {
        await repo.updateTransaction(widget.transaction.id, transactionData);
      }

      if (_isRecurring) {
        DateTime nextDate = _selectedDate;
        switch (_frequency) {
          case 'daily':
            nextDate = nextDate.add(const Duration(days: 1));
            break;
          case 'weekly':
            nextDate = nextDate.add(const Duration(days: 7));
            break;
          case 'biweekly':
            nextDate = nextDate.add(const Duration(days: 14));
            break;
          case 'monthly':
            nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day);
            break;
          case 'yearly':
            nextDate = DateTime(nextDate.year + 1, nextDate.month, nextDate.day);
            break;
        }

        final recurringData = RecurringTransaction(
          id: '',
          description: _descriptionController.text,
          amount: CurrencyFormatter.parse(_amountController.text, currency: _currency),
          categoryId: transactionData['category_id'] as String?,
          accountId: _selectedAccountId,
          type: _selectedType,
          frequency: _frequency,
          nextRunDate: nextDate,
          isActive: true,
          currency: _currency,
        );

        await repo.addRecurringTransaction(recurringData);
        ref.invalidate(recurringTransactionsProvider);
      }

      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(budgetsProvider);
      ref.invalidate(categoryAccumulatedBalancesProvider); // Budgets might change

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_isRecurring
                  ? 'Transaction updated and recurrence created'
                  : 'Transaction updated successfully')),
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
      ref.invalidate(categoryAccumulatedBalancesProvider);
      
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
    // Swap legs are part of a linked pair (shared swap_group_id) and must be
    // edited together, which this generic dialog doesn't support. Render a
    // read-only explanation instead of crashing on the type dropdown.
    if (widget.transaction.type == 'swap') {
      return Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: kDialogPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Swap transaction'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'This row is one leg of a linked swap and can\'t be edited '
                'here. To change it, open the investment account and delete '
                'the swap, then re-create it.',
              ),
            ],
          ),
        ),
      );
    }

    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.transaction.isInstallmentParent
                          ? 'Edit Installment Purchase'
                          : 'Edit Transaction',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Installment child banner
              if (widget.transaction.isInstallmentChild) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Installment ${widget.transaction.installmentNumber} of ${widget.transaction.numCuotas} — generated from purchase',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open parent purchase'),
                  onPressed: () async {
                    final parentId = widget.transaction.parentTransactionId;
                    if (parentId == null) return;
                    final parent = await ref
                        .read(financeRepositoryProvider)
                        .getInstallmentParent(parentId);
                    if (!mounted || parent == null) return;
                    Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      builder: (_) =>
                          EditTransactionDialog(transaction: parent),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],

              // Installment parent warning
              if (widget.transaction.isInstallmentParent) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .tertiaryContainer
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editing this installment purchase will regenerate all future installments. Paid cuotas will keep their status.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 8),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Currency toggle (CC transactions)
                      Builder(builder: (context) {
                        final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
                        final account = _flattenAccounts(accounts)
                            .firstWhereOrNull((a) => a.id == _selectedAccountId);
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

                      // Amount (read-only for installment children)
                      TextFormField(
                        controller: _amountController,
                        enabled: !widget.transaction.isInstallmentChild,
                        decoration: InputDecoration(
                          labelText: widget.transaction.isInstallmentChild
                              ? 'Amount (managed by parent purchase)'
                              : 'Amount',
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
                      const SizedBox(height: 10),

                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),

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
                      const SizedBox(height: 10),
                      
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
                      const SizedBox(height: 10),

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
                      const SizedBox(height: 10),

                      // Account
                      accountsAsync.when(
                        data: (accounts) {
                          final selectedAccount = _selectedAccountId == null
                              ? null
                              : _flattenAccounts(accounts).firstWhereOrNull(
                                  (a) => a.id == _selectedAccountId);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                value: _selectedAccountId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Account',
                                  border: OutlineInputBorder(),
                                ),
                                items: _buildAccountItems(accounts),
                                onChanged: (value) => setState(() => _selectedAccountId = value),
                              ),
                              if (selectedAccount != null &&
                                  selectedAccount.type == 'credit_card' &&
                                  selectedAccount.creditCardRules != null)
                                CreditCardBillingSubtitle(
                                  account: selectedAccount,
                                  transactionDate: _selectedDate,
                                ),
                            ],
                          );
                        },
                        loading: () => const CircularProgressIndicator(),
                        error: (e, s) => Text('Error loading accounts: $e'),
                      ),
                      const SizedBox(height: 10),

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
                                    child: Text('${cat.name} > ${sub.name}', style: const TextStyle(fontSize: 13)),
                                  ));
                                }
                              } else {
                                dropdownItems.add(DropdownMenuItem(
                                  value: cat.id,
                                  child: Text(cat.name, style: const TextStyle(fontSize: 13)),
                                ));
                              }
                            }
                            
                            // Validate selection exists in new list (type change handling)
                            // If simpler check needed:
                            bool selectionExists = dropdownItems.any((item) => item.value == _selectedCategoryId);
                            String? currentValue = selectionExists ? _selectedCategoryId : null;
                            
                            return DropdownButtonFormField<String>(
                              value: currentValue,
                              isExpanded: true,
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
                      if (_selectedType != 'transfer') const SizedBox(height: 10),

                      // Target Account
                      if (_selectedType == 'transfer')
                        accountsAsync.when(
                          data: (accounts) => DropdownButtonFormField<String>(
                            value: _selectedTargetAccountId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Destination Account',
                              border: OutlineInputBorder(),
                            ),
                            items: _buildAccountItems(accounts,
                                excludeId: _selectedAccountId),
                            onChanged: (value) => setState(() => _selectedTargetAccountId = value),
                          ),
                          loading: () => const CircularProgressIndicator(),
                          error: (e, s) => Text('Error loading accounts: $e'),
                        ),
                      if (_selectedType == 'transfer') const SizedBox(height: 10),

                      // Sinking-fund linkage (Model B): expense → funded by, transfer → contribution.
                      if (_selectedType == 'expense' || _selectedType == 'transfer')
                        categoriesAsync.when(
                          data: (categories) {
                            final savings = categories
                                .where((c) => c.isSavings)
                                .toList();
                            if (savings.isEmpty) return const SizedBox();
                            final isExpense = _selectedType == 'expense';
                            final selected = isExpense
                                ? _fundedByCategoryId
                                : _savingsContributionCategoryId;
                            final exists =
                                savings.any((c) => c.id == selected);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: DropdownButtonFormField<String?>(
                                value: exists ? selected : null,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: isExpense
                                      ? 'Funded by sinking fund (optional)'
                                      : 'Contribute to sinking fund (optional)',
                                  helperText: isExpense
                                      ? "Subtracts from the fund's accumulated balance instead of the category budget."
                                      : "Counts as this month's contribution toward the fund's target.",
                                  border: const OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                      value: null, child: Text('None')),
                                  ...savings.map((c) =>
                                      DropdownMenuItem<String?>(
                                        value: c.id,
                                        child: Text(c.name,
                                            overflow: TextOverflow.ellipsis),
                                      )),
                                ],
                                onChanged: (v) => setState(() {
                                  if (isExpense) {
                                    _fundedByCategoryId = v;
                                  } else {
                                    _savingsContributionCategoryId = v;
                                  }
                                }),
                              ),
                            );
                          },
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox(),
                        ),

                      // Installment parent: cuota config fields
                      if (widget.transaction.isInstallmentParent) ...[
                        const Divider(),
                        const Text('Installment settings',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: _cuotasOptions.contains(_numCuotas)
                              ? _numCuotas
                              : 12,
                          decoration: const InputDecoration(
                            labelText: 'Number of installments',
                            border: OutlineInputBorder(),
                          ),
                          items: _cuotasOptions
                              .map((n) =>
                                  DropdownMenuItem(value: n, child: Text('$n')))
                              .toList(),
                          onChanged: (v) => setState(() => _numCuotas = v!),
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          title: const Text('Interest-free'),
                          value: _interestFree,
                          onChanged: (v) =>
                              setState(() => _interestFree = v ?? true),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (!_interestFree) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _interestRateController,
                            decoration: const InputDecoration(
                              labelText: 'Monthly interest rate (%)',
                              suffixText: '%',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 10),
                      ],

                      // Make recurring (not available for installment parent/child)
                      if (!widget.transaction.isInstallmentParent &&
                          !widget.transaction.isInstallmentChild) ...[
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Make recurring?'),
                          subtitle: const Text(
                              'Automatically create future transactions from this one'),
                          value: _isRecurring,
                          onChanged: (v) => setState(() => _isRecurring = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_isRecurring) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _frequency,
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
                          const SizedBox(height: 10),
                        ],
                      ],

                      // Notes
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        // Child transactions: notes are always editable
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _isLoading ? null : _updateTransaction,
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _isLoading ? null : _deleteTransaction,
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
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
