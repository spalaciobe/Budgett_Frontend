import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import '../../data/repositories/bank_repository.dart';
import '../../data/models/bank_model.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_header.dart';
import 'package:budgett_frontend/presentation/widgets/common/currency_form_field.dart';

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
  final _cutoffDayController = TextEditingController();
  final _paymentDayController = TextEditingController();

  String _selectedType = 'checking';
  String? _selectedIcon;
  Bank? _selectedBank;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    _cutoffDayController.dispose();
    _paymentDayController.dispose();
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

  /// Pre-fill default days when the bank is selected.
  void _onBankSelected(Bank? bank) {
    setState(() {
      _selectedBank = bank;
      if (bank == null) return;

      switch (bank.code) {
        case 'NUBANK':
          _cutoffDayController.text = '25';
          _paymentDayController.text = '7';
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

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final accountData = <String, dynamic>{
      'name': _nameController.text.trim(),
      'type': _selectedType,
      'balance': CurrencyFormatter.parse(_balanceController.text),
      'icon': _selectedIcon,
    };

    if (_selectedType == 'credit_card') {
      accountData['credit_limit'] = _creditLimitController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_creditLimitController.text);

      if (_selectedBank != null) {
        final cutoffDay = int.tryParse(_cutoffDayController.text);
        final paymentDay = int.tryParse(_paymentDayController.text);

        accountData['credit_card_details'] = buildCreditCardRulesForBank(
          bank: _selectedBank!,
          cutoffDay: cutoffDay,
          paymentDay: paymentDay,
        );
      }
    }

    try {
      await ref.read(financeRepositoryProvider).createAccount(accountData);
      ref.invalidate(accountsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta creada exitosamente')),
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
                // Header
                const DialogHeader(title: 'Agregar cuenta'),
                const SizedBox(height: 24),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la cuenta',
                    border: OutlineInputBorder(),
                    hintText: 'Ej: Bancolombia Ahorros, Nubank TC',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),

                // Type
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de cuenta',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'checking',
                        child: Text('Cuenta Corriente')),
                    DropdownMenuItem(
                        value: 'savings',
                        child: Text('Cuenta de Ahorros')),
                    DropdownMenuItem(
                        value: 'credit_card',
                        child: Text('Tarjeta de Crédito')),
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(
                        value: 'investment',
                        child: Text('Inversión')),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedType = v!;
                    if (v == 'credit_card') _selectedIcon = 'credit_card';
                  }),
                ),
                const SizedBox(height: 16),

                // Balance
                CurrencyFormField(
                  controller: _balanceController,
                  labelText: isCreditCard
                      ? 'Saldo actual (deuda negativa)'
                      : 'Saldo inicial',
                  helperText: isCreditCard
                      ? 'Ingresa negativo si tienes deuda activa.'
                      : null,
                  allowNegative: true,
                ),
                const SizedBox(height: 16),

                // Icon selector
                DropdownButtonFormField<String>(
                  value: _selectedIcon,
                  decoration: const InputDecoration(
                    labelText: 'Ícono (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: null, child: Text('Por defecto')),
                    DropdownMenuItem(
                        value: 'account_balance',
                        child: Row(children: [
                          Icon(Icons.account_balance, size: 18),
                          SizedBox(width: 8),
                          Text('Banco')
                        ])),
                    DropdownMenuItem(
                        value: 'credit_card',
                        child: Row(children: [
                          Icon(Icons.credit_card, size: 18),
                          SizedBox(width: 8),
                          Text('Tarjeta')
                        ])),
                    DropdownMenuItem(
                        value: 'money',
                        child: Row(children: [
                          Icon(Icons.money, size: 18),
                          SizedBox(width: 8),
                          Text('Efectivo')
                        ])),
                    DropdownMenuItem(
                        value: 'savings',
                        child: Row(children: [
                          Icon(Icons.savings, size: 18),
                          SizedBox(width: 8),
                          Text('Ahorros')
                        ])),
                    DropdownMenuItem(
                        value: 'trending_up',
                        child: Row(children: [
                          Icon(Icons.trending_up, size: 18),
                          SizedBox(width: 8),
                          Text('Inversión')
                        ])),
                  ],
                  onChanged: (v) => setState(() => _selectedIcon = v),
                ),

                // ── Credit card section ───────────────────────────────────
                if (isCreditCard) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  Text('Detalles de la tarjeta',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),

                  // Bank selector
                  banksAsync.when(
                    data: (banks) => DropdownButtonFormField<Bank>(
                      value: _selectedBank,
                      decoration: const InputDecoration(
                        labelText: 'Banco emisor',
                        border: OutlineInputBorder(),
                      ),
                      items: banks
                          .map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(b.name),
                              ))
                          .toList(),
                      onChanged: _onBankSelected,
                      validator: (v) =>
                          v == null ? 'Selecciona el banco' : null,
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error cargando bancos: $e'),
                  ),
                  const SizedBox(height: 16),

                  // Credit limit
                  CurrencyFormField(
                    controller: _creditLimitController,
                    labelText: 'Cupo total',
                    required: false,
                  ),

                  // RappiCard: auto-rules notice
                  if (_bankHasAutoRules) ...[
                    const SizedBox(height: 16),
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
                              'RappiCard: corte el penúltimo día hábil del mes, pago 10 días después. Configuración automática.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Manual cutoff/payment days (non-Rappi)
                  if (_needsManualDays) ...[
                    const SizedBox(height: 16),
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
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Requerido' : null,
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
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Requerido' : null,
                          ),
                        ),
                      ],
                    ),
                    if (_selectedBank != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Festivos y fines de semana se ajustan automáticamente según las reglas de ${_selectedBank!.name}.',
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

                const SizedBox(height: 24),

                // Save
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveAccount,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Crear cuenta'),
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
