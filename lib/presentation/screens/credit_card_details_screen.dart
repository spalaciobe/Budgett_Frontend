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

// Provider to fetch transactions for a specific account
final accountTransactionsProvider = FutureProvider.family.autoDispose<List<Transaction>, String>((ref, accountId) async {
  final repo = ref.read(financeRepositoryProvider);
  return repo.getTransactionsForAccount(accountId, limit: 100);
});

class CreditCardDetailsScreen extends ConsumerWidget {
  final Account account;

  const CreditCardDetailsScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch transactions for this account
    final transactionsAsync = ref.watch(accountTransactionsProvider(account.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
               showDialog(
                context: context,
                builder: (context) => EditAccountDialog(account: account),
              ).then((_) {
                 // Refresh account data if needed (usually handled by provider stream/updates)
                 ref.invalidate(accountsProvider); // Global refresh to be safe
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
              account: account,
              transactionDate: DateTime.now(),
            ),

            const SizedBox(height: 24),

            // 2. Reglas de corte y pago
            _buildRulesSection(context, ref),

            const SizedBox(height: 24),

            // 3. Account Stats — COP slice
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Disponible COP',
                    account.creditLimit > 0 ? account.creditLimit + account.balance : 0,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Usado COP',
                    account.balance.abs(),
                    Colors.red,
                  ),
                ),
              ],
            ),

            // USD slice (only shown when the account has USD activity)
            if (account.creditLimitUsd > 0 || account.balanceUsd != 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      'Disponible USD',
                      account.creditLimitUsd > 0
                          ? account.creditLimitUsd + account.balanceUsd
                          : 0,
                      Colors.green,
                      currency: 'USD',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      'Usado USD',
                      account.balanceUsd.abs(),
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
                if (transactions.isEmpty) return const Text('No hay transacciones.');

                // Group by (billingPeriod, currency) — key = "YYYY-MM::COP"
                final Map<String, List<Transaction>> grouped = {};
                for (var t in transactions) {
                  final period = t.billingPeriod ?? 'Sin asignar';
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
                                    DateFormat('d MMM', 'es_CO').format(t.date),
                                    style: const TextStyle(fontSize: 11)),
                                if (isCrossPayment && t.fxRate != null)
                                  Text(
                                    'Pago en COP @ \$${NumberFormat('#,###', 'es_CO').format(t.fxRate!.toInt())}',
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

  Widget _buildRulesSection(BuildContext context, WidgetRef ref) {
    final rules = account.creditCardRules;
    final banksAsync = ref.watch(banksFutureProvider);

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
                'No hay reglas de corte y pago configuradas',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _showRulesBottomSheet(context, ref),
                icon: const Icon(Icons.settings),
                label: const Text('Configurar reglas'),
              ),
            ],
          ),
        ),
      );
    }

    return banksAsync.when(
      data: (banks) {
        final bank = banks.where((b) => b.id == rules.bankId).firstOrNull;
        final bankName = bank?.name ?? 'Banco desconocido';

        // Calculate next 3 months of dates
        final now = DateTime.now();
        final upcomingDates = <_CutoffPaymentPair>[];
        if (bank != null) {
          for (int i = 0; i < 3; i++) {
            final targetDate = DateTime(now.year, now.month + i);
            final cutoff = CreditCardCalculator.calculateCutoffDate(
              rules, bank, targetDate.year, targetDate.month,
            );
            final payment = CreditCardCalculator.calculatePaymentDate(
              rules, bank, cutoff,
            );
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
                      'Reglas de corte y pago',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showRulesBottomSheet(context, ref),
                      tooltip: 'Editar reglas',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildRuleRow(context, Icons.account_balance, 'Banco', bankName),
                const SizedBox(height: 6),
                _buildRuleRow(
                  context,
                  Icons.content_cut,
                  'Corte',
                  _describeCutoffRule(rules),
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 6),
                _buildRuleRow(
                  context,
                  Icons.payment,
                  'Pago',
                  _describePaymentRule(rules),
                  color: Colors.green,
                ),
                if (upcomingDates.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Próximas fechas',
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
          child: Text('Error cargando bancos: $e'),
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
    final dateFormat = DateFormat('d MMM yyyy', 'es');
    final monthFormat = DateFormat('MMMM', 'es');
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
      return 'Día ${rules.nominalCutoffDay}';
    }
    switch (rules.relativeCutoffType) {
      case RelativeCutoffType.secondToLastBusinessDay:
        return 'Penúltimo día hábil';
      case RelativeCutoffType.lastBusinessDay:
        return 'Último día hábil';
      case RelativeCutoffType.firstBusinessDay:
        return 'Primer día hábil';
      default:
        return 'Relativo';
    }
  }

  String _describePaymentRule(CreditCardRules rules) {
    if (rules.paymentType == PaymentType.fixed) {
      final month = rules.paymentMonth == 'siguiente' ? ' del siguiente mes' : '';
      return 'Día ${rules.nominalPaymentDay}$month';
    }
    final offsetLabel = rules.paymentOffsetType == OffsetType.business ? 'hábiles' : 'calendario';
    return '${rules.daysAfterCutoff} días $offsetLabel después del corte';
  }

  void _showRulesBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CreditCardRulesBottomSheet(
        account: account,
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
        return DateFormat('MMMM yyyy', 'es_CO').format(date);
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
          const SnackBar(content: Text('Reglas actualizadas')),
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
              'Reglas de corte y pago',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Bank selector
            banksAsync.when(
              data: (banks) => DropdownButtonFormField<Bank>(
                value: _selectedBank,
                decoration: const InputDecoration(
                  labelText: 'Banco emisor',
                  border: OutlineInputBorder(),
                ),
                items: banks
                    .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
                    .toList(),
                onChanged: _onBankSelected,
                validator: (v) => v == null ? 'Selecciona el banco' : null,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error cargando bancos: $e'),
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
                        'Reglas automáticas — corte penúltimo día hábil, pago 10 días después',
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
                        labelText: 'Día de corte',
                        border: OutlineInputBorder(),
                        hintText: '1–31',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requerido';
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
                        labelText: 'Día de pago',
                        border: OutlineInputBorder(),
                        hintText: '1–31',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requerido';
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

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
