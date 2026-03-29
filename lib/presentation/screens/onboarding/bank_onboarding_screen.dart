import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/bank_model.dart';
import '../../../data/repositories/bank_repository.dart';
import '../../providers/finance_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/bank_card_widget.dart';

// ---------------------------------------------------------------------------
// State for the multi-step onboarding wizard
// ---------------------------------------------------------------------------

enum _OnboardingStep { selectBanks, addAccounts, done }

class _BankAccountDraft {
  final Bank bank;
  String accountName;
  String accountType; // 'checking' | 'savings' | 'credit_card'
  double balance;
  double creditLimit;
  int? cutoffDay;
  int? paymentDay;

  _BankAccountDraft({
    required this.bank,
    this.accountName = '',
    this.accountType = 'checking',
    this.balance = 0,
    this.creditLimit = 0,
    this.cutoffDay,
    this.paymentDay,
  });

  bool get isCreditCard => accountType == 'credit_card';
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class BankOnboardingScreen extends ConsumerStatefulWidget {
  const BankOnboardingScreen({super.key});

  @override
  ConsumerState<BankOnboardingScreen> createState() => _BankOnboardingScreenState();
}

class _BankOnboardingScreenState extends ConsumerState<BankOnboardingScreen> {
  _OnboardingStep _step = _OnboardingStep.selectBanks;
  final Set<String> _selectedBankIds = {};
  final List<_BankAccountDraft> _drafts = [];
  bool _isSaving = false;
  String? _error;

  // -------------------------------------------------------------------------
  // Step 1: Bank selection
  // -------------------------------------------------------------------------

  Widget _buildSelectBanksStep(List<Bank> banks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¡Bienvenido a Budgett! 👋',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '¿Con qué bancos trabajas? Selecciona los que uses y pre-configuramos las reglas de corte y pago automáticamente.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Bank list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: banks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final bank = banks[index];
              return BankCard(
                bank: bank,
                isSelected: _selectedBankIds.contains(bank.id),
                onTap: () => setState(() {
                  if (_selectedBankIds.contains(bank.id)) {
                    _selectedBankIds.remove(bank.id);
                  } else {
                    _selectedBankIds.add(bank.id);
                  }
                }),
              );
            },
          ),
        ),

        // CTA
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_selectedBankIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Selecciona al menos un banco para continuar.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton(
                onPressed: _selectedBankIds.isEmpty
                    ? null
                    : () {
                        final selectedBanks =
                            banks.where((b) => _selectedBankIds.contains(b.id)).toList();
                        setState(() {
                          _drafts.clear();
                          for (final bank in selectedBanks) {
                            _drafts.add(_BankAccountDraft(
                              bank: bank,
                              accountName: bank.name,
                              // Default to credit_card for cards, checking otherwise
                              accountType: (bank.code == 'RAPPICARD' ||
                                      bank.code == 'NUBANK')
                                  ? 'credit_card'
                                  : 'checking',
                            ));
                          }
                          _step = _OnboardingStep.addAccounts;
                        });
                      },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Continuar'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _skipOnboarding,
                child: const Text('Omitir por ahora'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Step 2: Configure each account draft
  // -------------------------------------------------------------------------

  Widget _buildAddAccountsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configura tus cuentas',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Ingresa los detalles de cada cuenta. Las reglas de corte y pago se configuran automáticamente según el banco.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _drafts.length,
            itemBuilder: (context, index) => _AccountDraftCard(
              draft: _drafts[index],
              onChanged: () => setState(() {}),
            ),
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _isSaving ? null : _saveAccounts,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Crear cuentas'),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _step = _OnboardingStep.selectBanks),
                child: const Text('← Volver'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _saveAccounts() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final repo = ref.read(financeRepositoryProvider);

      for (final draft in _drafts) {
        final accountData = <String, dynamic>{
          'name': draft.accountName.trim().isEmpty ? draft.bank.name : draft.accountName.trim(),
          'type': draft.accountType,
          'balance': draft.balance,
          'icon': draft.isCreditCard ? 'credit_card' : 'account_balance',
        };

        if (draft.isCreditCard) {
          accountData['credit_limit'] = draft.creditLimit;
          accountData['credit_card_details'] = _buildCreditCardRules(draft);
        }

        await repo.createAccount(accountData);
      }

      // Mark onboarding as done
      await ref.read(onboardingNotifierProvider.notifier).markCompleted();
      ref.invalidate(accountsProvider);

      if (mounted) context.go('/');
    } catch (e) {
      setState(() {
        _error = 'Error al guardar: $e';
        _isSaving = false;
      });
    }
  }

  Map<String, dynamic> _buildCreditCardRules(_BankAccountDraft draft) {
    final bank = draft.bank;

    switch (bank.code) {
      case 'RAPPICARD':
        return {
          'banco_id': bank.id,
          'tipo_corte': 'relativo',
          'corte_relativo_tipo': 'penultimo_dia_habil',
          'tipo_pago': 'relativo_dias',
          'dias_despues_corte': 10,
          'tipo_offset_pago': 'calendario',
        };

      case 'NUBANK':
        // Nubank: fixed cutoff day 25, payment day 7 of following month
        return {
          'banco_id': bank.id,
          'tipo_corte': 'fijo',
          'dia_corte_nominal': draft.cutoffDay ?? 25,
          'tipo_pago': 'fijo',
          'dia_pago_nominal': draft.paymentDay ?? 7,
          'mes_pago': 'siguiente',
          'tipo_offset_pago': 'habiles',
        };

      case 'BANCOLOMBIA':
      case 'DAVIVIENDA':
      case 'BBVA':
      default:
        return {
          'banco_id': bank.id,
          'tipo_corte': 'fijo',
          'dia_corte_nominal': draft.cutoffDay ?? 15,
          'tipo_pago': 'fijo',
          'dia_pago_nominal': draft.paymentDay ?? 30,
          'mes_pago': 'siguiente',
          'tipo_offset_pago': 'calendario',
        };
    }
  }

  Future<void> _skipOnboarding() async {
    await ref.read(onboardingNotifierProvider.notifier).markCompleted();
    if (mounted) context.go('/');
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final banksAsync = ref.watch(banksFutureProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: banksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error al cargar bancos: $e'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(banksFutureProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
          data: (banks) {
            if (_step == _OnboardingStep.selectBanks) {
              return _buildSelectBanksStep(banks);
            }
            return _buildAddAccountsStep();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widget: editable card for one account draft
// ---------------------------------------------------------------------------

class _AccountDraftCard extends StatefulWidget {
  final _BankAccountDraft draft;
  final VoidCallback onChanged;

  const _AccountDraftCard({required this.draft, required this.onChanged});

  @override
  State<_AccountDraftCard> createState() => _AccountDraftCardState();
}

class _AccountDraftCardState extends State<_AccountDraftCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  late final TextEditingController _limitCtrl;
  late final TextEditingController _cutoffCtrl;
  late final TextEditingController _paymentCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _nameCtrl = TextEditingController(text: d.accountName);
    _balanceCtrl = TextEditingController();
    _limitCtrl = TextEditingController();
    _cutoffCtrl = TextEditingController(text: d.cutoffDay?.toString() ?? '');
    _paymentCtrl = TextEditingController(text: d.paymentDay?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _limitCtrl.dispose();
    _cutoffCtrl.dispose();
    _paymentCtrl.dispose();
    super.dispose();
  }

  bool get _isRappiCard => widget.draft.bank.code == 'RAPPICARD';
  bool get _requiresCutoffPayment =>
      widget.draft.isCreditCard && !_isRappiCard;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bank name header
            Row(
              children: [
                const Icon(Icons.account_balance, size: 20),
                const SizedBox(width: 8),
                Text(
                  draft.bank.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // Account name
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de la cuenta',
                border: OutlineInputBorder(),
                helperText: 'Ej: Bancolombia Ahorros, Nubank TC',
              ),
              onChanged: (v) {
                draft.accountName = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 12),

            // Account type
            DropdownButtonFormField<String>(
              value: draft.accountType,
              decoration: const InputDecoration(
                labelText: 'Tipo de cuenta',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'checking', child: Text('Cuenta Corriente')),
                DropdownMenuItem(value: 'savings', child: Text('Cuenta de Ahorros')),
                DropdownMenuItem(value: 'credit_card', child: Text('Tarjeta de Crédito')),
              ],
              onChanged: (v) => setState(() {
                draft.accountType = v!;
                widget.onChanged();
              }),
            ),
            const SizedBox(height: 12),

            // Balance
            TextField(
              controller: _balanceCtrl,
              decoration: InputDecoration(
                labelText: draft.isCreditCard ? 'Saldo actual (deuda, negativo)' : 'Saldo inicial',
                prefixText: '\$',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [CurrencyInputFormatter()],
              onChanged: (v) {
                draft.balance = CurrencyFormatter.parse(v);
                widget.onChanged();
              },
            ),

            // Credit card specific
            if (draft.isCreditCard) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _limitCtrl,
                decoration: const InputDecoration(
                  labelText: 'Cupo total',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CurrencyInputFormatter()],
                onChanged: (v) {
                  draft.creditLimit = CurrencyFormatter.parse(v);
                  widget.onChanged();
                },
              ),

              // Rappi: automatic rules notice
              if (_isRappiCard) ...[
                const SizedBox(height: 12),
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
                          'Reglas automáticas: corte el penúltimo día hábil, pago 10 días después.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Fixed cutoff/payment days (non-Rappi cards)
              if (_requiresCutoffPayment) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cutoffCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Día de corte',
                          border: OutlineInputBorder(),
                          hintText: '1-31',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          draft.cutoffDay = int.tryParse(v);
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _paymentCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Día de pago',
                          border: OutlineInputBorder(),
                          hintText: '1-31',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          draft.paymentDay = int.tryParse(v);
                          widget.onChanged();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Festivos y fines de semana se ajustan automáticamente según las reglas de ${draft.bank.name}.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                      ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
