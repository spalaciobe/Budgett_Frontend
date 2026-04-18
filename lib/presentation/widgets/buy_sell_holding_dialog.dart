import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/investment_holding_model.dart';
import '../../data/repositories/finance_repository.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

/// Shared dialog for both Buy and Sell actions.
/// [isBuy] = true → records expense + increases quantity.
/// [isBuy] = false → records income + decreases quantity.
class BuySellHoldingDialog extends ConsumerStatefulWidget {
  final String accountId;
  final InvestmentHolding holding;
  final bool isBuy;

  const BuySellHoldingDialog({
    super.key,
    required this.accountId,
    required this.holding,
    required this.isBuy,
  });

  @override
  ConsumerState<BuySellHoldingDialog> createState() =>
      _BuySellHoldingDialogState();
}

class _BuySellHoldingDialogState extends ConsumerState<BuySellHoldingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with last known price
    _priceCtrl.text = CurrencyFormatter.format(
      widget.holding.currentPrice,
      currency: widget.holding.currency,
      includeSymbol: false,
    );
    _descCtrl.text = widget.isBuy
        ? 'Buy ${widget.holding.symbol}'
        : 'Sell ${widget.holding.symbol}';
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _feeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final price = CurrencyFormatter.parse(_priceCtrl.text,
        currency: widget.holding.currency);
    final fee = _feeCtrl.text.isEmpty
        ? 0.0
        : CurrencyFormatter.parse(_feeCtrl.text,
            currency: widget.holding.currency);

    final txData = {
      'description': _descCtrl.text.trim(),
      'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      'movement_type': 'variable',
    };

    final repo = ref.read(financeRepositoryProvider);
    try {
      if (widget.isBuy) {
        await repo.buyHolding(
          accountId: widget.accountId,
          holdingId: widget.holding.id,
          quantity: qty,
          pricePerUnit: price,
          fee: fee,
          currency: widget.holding.currency,
          transactionData: txData,
        );
      } else {
        await repo.sellHolding(
          accountId: widget.accountId,
          holdingId: widget.holding.id,
          quantity: qty,
          pricePerUnit: price,
          fee: fee,
          currency: widget.holding.currency,
          transactionData: txData,
        );
      }
      ref.invalidate(accountHoldingsProvider(widget.accountId));
      ref.invalidate(accountsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = widget.isBuy;
    final h = widget.holding;
    final currency = h.currency;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 580),
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
                      child: Text(
                        isBuy ? 'Buy ${h.symbol}' : 'Sell ${h.symbol}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Current position: ${CurrencyFormatter.formatQuantity(h.quantity)} ${h.symbol}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                ),
                const SizedBox(height: 20),

                // Quantity
                TextFormField(
                  controller: _qtyCtrl,
                  decoration: InputDecoration(
                    labelText: isBuy ? 'Quantity to Buy' : 'Quantity to Sell',
                    border: const OutlineInputBorder(),
                    hintText: '0.00000000',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final qty = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                    if (qty <= 0) return 'Must be > 0';
                    if (!isBuy && qty > h.quantity) {
                      return 'Exceeds current position (${CurrencyFormatter.formatQuantity(h.quantity)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Price
                TextFormField(
                  controller: _priceCtrl,
                  decoration: InputDecoration(
                    labelText: 'Price per Unit',
                    prefixText: CurrencyFormatter.prefixFor(currency),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter(currency: currency)],
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),

                // Fee (optional)
                TextFormField(
                  controller: _feeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Fee / Commission (optional)',
                    prefixText: CurrencyFormatter.prefixFor(currency),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter(currency: currency)],
                ),
                const SizedBox(height: 8),

                // Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: isBuy
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.secondary,
                          ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(isBuy ? 'Confirm Buy' : 'Confirm Sell'),
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
