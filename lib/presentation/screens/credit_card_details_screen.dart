import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/utils/credit_card_calculator.dart';
import '../../data/models/account_model.dart';
import '../../data/models/bank_model.dart';
import '../../data/models/credit_card_rules_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/repositories/bank_repository.dart';
import '../../presentation/providers/finance_provider.dart';
import '../../presentation/utils/currency_formatter.dart';
import '../../presentation/widgets/add_account_dialog.dart';
import '../../presentation/widgets/credit_card_billing_simulator.dart';
import '../../presentation/widgets/edit_account_dialog.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────
final _monthNames = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];

// Provider to fetch transactions for a specific account
final accountTransactionsProvider = FutureProvider.family.autoDispose<List<Transaction>, String>((ref, accountId) async {
  final repo = ref.read(financeRepositoryProvider);
  return repo.getTransactionsForAccount(accountId, limit: 100);
});

class CreditCardDetailsScreen extends ConsumerWidget {
  final String accountId;

  const CreditCardDetailsScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref
        .watch(accountsProvider)
        .valueOrNull
        ?.where((a) => a.id == accountId)
        .toList();

    if (matches == null || matches.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Account freshAccount = matches.first;

    // Watch transactions for this account
    final transactionsAsync = ref.watch(accountTransactionsProvider(freshAccount.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(freshAccount.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
               showDialog(
                context: context,
                builder: (context) => EditAccountDialog(account: freshAccount),
              ).then((_) {
                 ref.invalidate(accountsProvider);
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Current Status Simulator (Projected for TODAY)
            Text('Current Billing Status',
                 style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            CreditCardBillingSimulator(
              account: freshAccount,
              transactionDate: DateTime.now(),
            ),

            const SizedBox(height: 24),

            // 2. Reglas de corte y pago
            _buildRulesSection(context, ref, freshAccount),

            const SizedBox(height: 24),

            // 3. Account Stats — COP slice
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Available COP',
                    freshAccount.creditLimit > 0 ? freshAccount.creditLimit + freshAccount.balance : 0,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Used COP',
                    freshAccount.balance.abs(),
                    Colors.red,
                  ),
                ),
              ],
            ),

            // USD slice (only shown when the account has USD activity)
            if (freshAccount.creditLimitUsd > 0 || freshAccount.balanceUsd != 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      'Available USD',
                      freshAccount.creditLimitUsd > 0
                          ? freshAccount.creditLimitUsd + freshAccount.balanceUsd
                          : 0,
                      Colors.green,
                      currency: 'USD',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      'Used USD',
                      freshAccount.balanceUsd.abs(),
                      Colors.red,
                      currency: 'USD',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),

            // 4. Transactions / Extracts List
            Text('Recent Transactions',
                 style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) return const Text('No transactions.');

                // Group by (billingPeriod, currency) — key = "YYYY-MM::COP"
                final Map<String, List<Transaction>> grouped = {};
                for (var t in transactions) {
                  final period = t.billingPeriod ?? 'Unassigned';
                  final key = '$period::${t.currency}';
                  grouped.putIfAbsent(key, () => []).add(t);
                }

                // Sort: newest period first, then COP before USD within same period
                final sortedKeys = grouped.keys.toList()
                  ..sort((a, b) {
                    final aParts = a.split('::');
                    final bParts = b.split('::');
                    final periodCmp = bParts[0].compareTo(aParts[0]);
                    if (periodCmp != 0) return periodCmp;
                    return aParts[1].compareTo(bParts[1]); // COP before USD
                  });

                return Column(
                  children: sortedKeys.asMap().entries.map((entry) {
                    final index = entry.key;
                    final key = entry.value;
                    final parts = key.split('::');
                    final period = parts[0];
                    final currency = parts.length > 1 ? parts[1] : 'COP';
                    final periodTransactions = grouped[key]!;
                    final total = periodTransactions.fold(0.0, (sum, t) => sum + t.amount);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                      child: ExpansionTile(
                        initiallyExpanded: index == 0,
                        shape: const Border(),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatPeriod(period),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: currency == 'USD'
                                    ? Colors.blue.withOpacity(0.12)
                                    : Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                currency,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: currency == 'USD'
                                      ? Colors.blue.shade700
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Total: ${CurrencyFormatter.format(total, currency: currency)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        children: periodTransactions.map((t) {
                          final isCrossPayment = t.isCrossCurrencyPayment;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0),
                            leading: CircleAvatar(
                              radius: 4,
                              backgroundColor: isCrossPayment
                                  ? Colors.green.withOpacity(0.6)
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.5),
                            ),
                            title: Text(t.description,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            trailing: Text(
                              CurrencyFormatter.format(t.amount, currency: t.currency),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    DateFormat('d MMM', 'en').format(t.date),
                                    style: const TextStyle(fontSize: 11)),
                                if (isCrossPayment && t.fxRate != null)
                                  Text(
                                    'Payment in COP @ \$${NumberFormat('#,###', 'en_US').format(t.fxRate!.toInt())}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade700),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Text('Error: $e'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRulesSection(BuildContext context, WidgetRef ref, Account acc) {
    final rules = acc.creditCardRules;
    final banksAsync = ref.watch(banksFutureProvider);

    // Watch calendar overrides so "Upcoming Dates" reflects manual edits
    final now = DateTime.now();
    final calendarThisYear = ref
        .watch(billingCalendarProvider((accountId: acc.id, year: now.year)))
        .valueOrNull ?? {};
    final calendarNextYear = ref
        .watch(billingCalendarProvider((accountId: acc.id, year: now.year + 1)))
        .valueOrNull ?? {};

    if (rules == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.rule, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text(
                'No statement and payment rules configured',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _showRulesBottomSheet(context, ref, acc),
                icon: const Icon(Icons.settings),
                label: const Text('Set up rules'),
              ),
            ],
          ),
        ),
      );
    }

    return banksAsync.when(
      data: (banks) {
        final bank = banks.where((b) => b.id == rules.bankId).firstOrNull;
        final bankName = bank?.name ?? 'Unknown bank';

        // Calculate next 3 months, merging with any calendar overrides
        final upcomingDates = <_CutoffPaymentPair>[];
        if (bank != null) {
          for (int i = 0; i < 3; i++) {
            final targetDate = DateTime(now.year, now.month + i);
            final overrides = targetDate.year == now.year
                ? calendarThisYear
                : calendarNextYear;
            final override = overrides[targetDate.month];
            final cutoff = override?.cutoff ??
                CreditCardCalculator.calculateCutoffDate(
                    rules, bank, targetDate.year, targetDate.month);
            final payment = override?.payment ??
                CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);
            upcomingDates.add(_CutoffPaymentPair(cutoff, payment));
          }
        }

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Statement & Payment Rules',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showRulesBottomSheet(context, ref, acc),
                      tooltip: 'Edit Rules',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildRuleRow(context, Icons.account_balance, 'Bank', bankName),
                const SizedBox(height: 6),
                _buildRuleRow(
                  context,
                  Icons.content_cut,
                  'Statement',
                  _describeCutoffRule(rules),
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 6),
                _buildRuleRow(
                  context,
                  Icons.payment,
                  'Payment',
                  _describePaymentRule(rules),
                  color: Colors.green,
                ),
                if (upcomingDates.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Upcoming Dates',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...upcomingDates.map((pair) => _buildDateRow(context, pair)),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error loading banks: $e'),
        ),
      ),
    );
  }

  Widget _buildRuleRow(BuildContext context, IconData icon, String label, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Widget _buildDateRow(BuildContext context, _CutoffPaymentPair pair) {
    final dateFormat = DateFormat('d MMM yyyy', 'en');
    final monthFormat = DateFormat('MMMM', 'en');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              monthFormat.format(pair.cutoff).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.content_cut, size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text(dateFormat.format(pair.cutoff), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.payment, size: 14, color: Colors.green),
                const SizedBox(width: 4),
                Text(dateFormat.format(pair.payment), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _describeCutoffRule(CreditCardRules rules) {
    if (rules.cutoffType == CutoffType.fixed) {
      return 'Day ${rules.nominalCutoffDay}';
    }
    switch (rules.relativeCutoffType) {
      case RelativeCutoffType.secondToLastBusinessDay:
        return 'Second-to-last business day';
      case RelativeCutoffType.lastBusinessDay:
        return 'Last business day';
      case RelativeCutoffType.firstBusinessDay:
        return 'First business day';
      default:
        return 'Relative';
    }
  }

  String _describePaymentRule(CreditCardRules rules) {
    if (rules.paymentType == PaymentType.fixed) {
      final month = rules.paymentMonth == 'siguiente' ? ' of next month' : '';
      return 'Day ${rules.nominalPaymentDay}$month';
    }
    final offsetLabel = rules.paymentOffsetType == OffsetType.business ? 'business' : 'calendar';
    return '${rules.daysAfterCutoff} $offsetLabel days after statement';
  }

  void _showRulesBottomSheet(BuildContext context, WidgetRef ref, Account acc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CreditCardRulesBottomSheet(
        account: acc,
        parentRef: ref,
      ),
    );
  }

  String _formatPeriod(String period) {
    if (period == 'Unassigned') return period;
    try {
      // Expect YYYY-MM
      final parts = period.split('-');
      if (parts.length == 2) {
        final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
        return DateFormat('MMMM yyyy', 'en').format(date);
      }
    } catch (_) {}
    return period;
  }


  Widget _buildStatCard(BuildContext context, String label, double amount, Color color, {String currency = 'COP'}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
               style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.format(amount, currency: currency),
               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _CutoffPaymentPair {
  final DateTime cutoff;
  final DateTime payment;
  _CutoffPaymentPair(this.cutoff, this.payment);
}

class _CreditCardRulesBottomSheet extends ConsumerStatefulWidget {
  final Account account;
  final WidgetRef parentRef;

  const _CreditCardRulesBottomSheet({
    required this.account,
    required this.parentRef,
  });

  @override
  ConsumerState<_CreditCardRulesBottomSheet> createState() => _CreditCardRulesBottomSheetState();
}

class _CreditCardRulesBottomSheetState extends ConsumerState<_CreditCardRulesBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cutoffDayController = TextEditingController();
  final _paymentDayController = TextEditingController();
  Bank? _selectedBank;
  bool _saving = false;

  bool get _isRappiCard => _selectedBank?.code == 'RAPPICARD';

  @override
  void initState() {
    super.initState();
    // Pre-fill from existing rules
    final rules = widget.account.creditCardRules;
    if (rules != null) {
      if (rules.nominalCutoffDay != null) {
        _cutoffDayController.text = rules.nominalCutoffDay.toString();
      }
      if (rules.nominalPaymentDay != null) {
        _paymentDayController.text = rules.nominalPaymentDay.toString();
      }
    }
  }

  @override
  void dispose() {
    _cutoffDayController.dispose();
    _paymentDayController.dispose();
    super.dispose();
  }

  void _onBankSelected(Bank? bank) {
    setState(() {
      _selectedBank = bank;
      if (bank == null) return;
      switch (bank.code) {
        case 'NUBANK':
          _cutoffDayController.text = '25';
          _paymentDayController.text = '7';
          break;
        case 'RAPPICARD':
          break;
        case 'BANCOLOMBIA':
        case 'DAVIVIENDA':
        case 'BBVA':
        default:
          _cutoffDayController.text = '15';
          _paymentDayController.text = '30';
      }
    });
  }

  Future<void> _save() async {
    if (!_isRappiCard && !_formKey.currentState!.validate()) return;
    if (_selectedBank == null) return;

    setState(() => _saving = true);

    try {
      final cutoffDay = int.tryParse(_cutoffDayController.text);
      final paymentDay = int.tryParse(_paymentDayController.text);

      final rulesMap = buildCreditCardRulesForBank(
        bank: _selectedBank!,
        cutoffDay: cutoffDay,
        paymentDay: paymentDay,
      );

      await ref.read(financeRepositoryProvider).updateAccount(
        widget.account.id,
        {'credit_card_details': rulesMap},
      );

      widget.parentRef.invalidate(accountsProvider);
      widget.parentRef.invalidate(accountTransactionsProvider(widget.account.id));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rules updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banksAsync = ref.watch(banksFutureProvider);

    // Pre-select bank from existing rules
    if (_selectedBank == null && widget.account.creditCardRules != null) {
      banksAsync.whenData((banks) {
        final match = banks.where((b) => b.id == widget.account.creditCardRules!.bankId).firstOrNull;
        if (match != null && _selectedBank == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedBank = match);
          });
        }
      });
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Statement & Payment Rules',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Bank selector
            banksAsync.when(
              data: (banks) => DropdownButtonFormField<Bank>(
                value: _selectedBank,
                decoration: const InputDecoration(
                  labelText: 'Issuing Bank',
                  border: OutlineInputBorder(),
                ),
                items: banks
                    .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
                    .toList(),
                onChanged: _onBankSelected,
                validator: (v) => v == null ? 'Select a bank' : null,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading banks: $e'),
            ),
            const SizedBox(height: 16),

            // RappiCard auto-rules info
            if (_isRappiCard)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF441A).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFF441A).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFFFF441A), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Automatic rules — statement on second-to-last business day, payment 10 days later',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),

            // Manual day fields (non-Rappi)
            if (_selectedBank != null && !_isRappiCard) ...[
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
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final n = int.tryParse(v);
                        if (n == null || n < 1 || n > 31) return '1–31';
                        return null;
                      },
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
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final n = int.tryParse(v);
                        if (n == null || n < 1 || n > 31) return '1–31';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Calendar override button — only when rules are already saved
            if (widget.account.creditCardRules != null && _selectedBank != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('View and edit yearly dates'),
                onPressed: () {
                  Navigator.of(context).pop(); // close rules sheet
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    constraints: const BoxConstraints(maxWidth: 720),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => _BillingCalendarSheet(
                      account: widget.account,
                      bank: _selectedBank!,
                      parentRef: widget.parentRef,
                    ),
                  );
                },
              ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Billing Calendar Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _BillingCalendarSheet extends ConsumerStatefulWidget {
  final Account account;
  final Bank bank;
  final WidgetRef parentRef;

  const _BillingCalendarSheet({
    required this.account,
    required this.bank,
    required this.parentRef,
  });

  @override
  ConsumerState<_BillingCalendarSheet> createState() =>
      _BillingCalendarSheetState();
}

class _BillingCalendarSheetState
    extends ConsumerState<_BillingCalendarSheet> {
  int _year = DateTime.now().year;
  final _fmt = DateFormat('d MMM', 'en');

  @override
  Widget build(BuildContext context) {
    final rules = widget.account.creditCardRules;
    if (rules == null) return const SizedBox();

    final calendarAsync = ref.watch(billingCalendarProvider(
        (accountId: widget.account.id, year: _year)));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Header + year selector
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Statement & Payment Dates',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _year--),
                ),
                Text('$_year',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _year++),
                ),
              ],
            ),
          ),

          // Column headers
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 4),
            child: Row(
              children: [
                const SizedBox(width: 120),
                Expanded(
                  child: Text('Statement',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                ),
                Expanded(
                  child: Text('Payment',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                ),
                const SizedBox(width: 96),
              ],
            ),
          ),
          const Divider(height: 1),

          // Months list
          Expanded(
            child: calendarAsync.when(
              data: (overrides) => ListView.separated(
                controller: scrollCtrl,
                itemCount: 12,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 20, endIndent: 20),
                itemBuilder: (ctx, i) {
                  final month = i + 1;
                  final calcCutoff = CreditCardCalculator.calculateCutoffDate(
                      rules, widget.bank, _year, month);
                  final calcPayment = CreditCardCalculator.calculatePaymentDate(
                      rules, widget.bank, calcCutoff);

                  final override = overrides[month];
                  final effectiveCutoff = override?.cutoff ?? calcCutoff;
                  final effectivePayment = override?.payment ?? calcPayment;
                  final isOverridden = override != null;

                  return _MonthRow(
                    monthName: _monthNames[i],
                    cutoff: effectiveCutoff,
                    payment: effectivePayment,
                    isOverridden: isOverridden,
                    fmt: _fmt,
                    onEdit: () => _editMonth(
                      ctx, month, effectiveCutoff, effectivePayment, overrides),
                    onReset: isOverridden
                        ? () => _resetMonth(month)
                        : null,
                  );
                },
              ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editMonth(
    BuildContext ctx,
    int month,
    DateTime currentCutoff,
    DateTime currentPayment,
    Map<int, ({DateTime cutoff, DateTime payment})> overrides,
  ) async {
    DateTime? newCutoff = currentCutoff;
    DateTime? newPayment = currentPayment;

    await showDialog<void>(
      context: ctx,
      builder: (dCtx) => _EditMonthDialog(
        monthName: _monthNames[month - 1],
        year: _year,
        initialCutoff: currentCutoff,
        initialPayment: currentPayment,
        onSave: (cutoff, payment) {
          newCutoff = cutoff;
          newPayment = payment;
        },
      ),
    );

    if (newCutoff == null || newPayment == null) return;
    if (newCutoff == currentCutoff && newPayment == currentPayment &&
        overrides[month] != null) return;

    try {
      await ref.read(financeRepositoryProvider).upsertBillingCalendarEntry(
            widget.account.id, _year, month, newCutoff!, newPayment!);
      ref.invalidate(billingCalendarProvider(
          (accountId: widget.account.id, year: _year)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _resetMonth(int month) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Date'),
        content: Text(
            'Revert to the auto-calculated date for ${_monthNames[month - 1]} $_year?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(financeRepositoryProvider).deleteBillingCalendarEntry(
            widget.account.id, _year, month);
      ref.invalidate(billingCalendarProvider(
          (accountId: widget.account.id, year: _year)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Month row widget
// ─────────────────────────────────────────────────────────────────────────────

class _MonthRow extends StatelessWidget {
  final String monthName;
  final DateTime cutoff;
  final DateTime payment;
  final bool isOverridden;
  final DateFormat fmt;
  final VoidCallback onEdit;
  final VoidCallback? onReset;

  const _MonthRow({
    required this.monthName,
    required this.cutoff,
    required this.payment,
    required this.isOverridden,
    required this.fmt,
    required this.onEdit,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final overrideColor = Theme.of(context).colorScheme.tertiary;
    final textStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: isOverridden ? overrideColor : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      child: Row(
        children: [
          // Month name
          SizedBox(
            width: 120,
            child: Row(
              children: [
                if (isOverridden)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.edit_note, size: 14, color: overrideColor),
                  ),
                Flexible(
                  child: Text(
                    monthName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isOverridden ? overrideColor : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Cutoff date
          Expanded(child: Text(fmt.format(cutoff), style: textStyle)),
          // Payment date
          Expanded(child: Text(fmt.format(payment), style: textStyle)),
          // Actions
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                if (onReset != null)
                  IconButton(
                    icon: Icon(Icons.restore, size: 18,
                        color: Theme.of(context).colorScheme.error),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reset',
                    onPressed: onReset,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit month dialog
// ─────────────────────────────────────────────────────────────────────────────

class _EditMonthDialog extends StatefulWidget {
  final String monthName;
  final int year;
  final DateTime initialCutoff;
  final DateTime initialPayment;
  final void Function(DateTime cutoff, DateTime payment) onSave;

  const _EditMonthDialog({
    required this.monthName,
    required this.year,
    required this.initialCutoff,
    required this.initialPayment,
    required this.onSave,
  });

  @override
  State<_EditMonthDialog> createState() => _EditMonthDialogState();
}

class _EditMonthDialogState extends State<_EditMonthDialog> {
  late DateTime _cutoff;
  late DateTime _payment;
  final _fmt = DateFormat('d MMM yyyy', 'en');

  @override
  void initState() {
    super.initState();
    _cutoff = widget.initialCutoff;
    _payment = widget.initialPayment;
  }

  Future<void> _pickDate({required bool isCutoff}) async {
    final initial = isCutoff ? _cutoff : _payment;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(widget.year - 1),
      lastDate: DateTime(widget.year + 2),
      useRootNavigator: false,
    );
    if (picked == null) return;
    setState(() {
      if (isCutoff) {
        _cutoff = picked;
      } else {
        _payment = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.monthName} ${widget.year}'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cutoff row
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.content_cut, color: Colors.orange),
              title: const Text('Statement Date'),
              subtitle: Text(_fmt.format(_cutoff),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              trailing: TextButton(
                onPressed: () => _pickDate(isCutoff: true),
                child: const Text('Change'),
              ),
            ),
            const SizedBox(height: 8),
            // Payment row
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.payment, color: Colors.green),
              title: const Text('Payment Date'),
              subtitle: Text(_fmt.format(_payment),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              trailing: TextButton(
                onPressed: () => _pickDate(isCutoff: false),
                child: const Text('Change'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_cutoff, _payment);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
