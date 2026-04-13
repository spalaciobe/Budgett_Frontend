import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/investment_holding_model.dart';
import '../../data/repositories/finance_repository.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

class EditHoldingDialog extends ConsumerStatefulWidget {
  final String accountId;
  final InvestmentHolding? holding; // null → create new

  const EditHoldingDialog({
    super.key,
    required this.accountId,
    this.holding,
  });

  @override
  ConsumerState<EditHoldingDialog> createState() => _EditHoldingDialogState();
}

class _EditHoldingDialogState extends ConsumerState<EditHoldingDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _symbolCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _avgCostCtrl;
  late TextEditingController _currentPriceCtrl;
  late TextEditingController _notesCtrl;
  late String _assetClass;
  late String _currency;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final h = widget.holding;
    _symbolCtrl = TextEditingController(text: h?.symbol ?? '');
    _nameCtrl = TextEditingController(text: h?.name ?? '');
    _qtyCtrl = TextEditingController(
      text: h != null ? CurrencyFormatter.formatQuantity(h.quantity) : '',
    );
    _avgCostCtrl = TextEditingController(
      text: h != null
          ? CurrencyFormatter.format(h.avgCost,
              currency: h.currency, includeSymbol: false)
          : '',
    );
    _currentPriceCtrl = TextEditingController(
      text: h != null
          ? CurrencyFormatter.format(h.currentPrice,
              currency: h.currency, includeSymbol: false)
          : '',
    );
    _notesCtrl = TextEditingController(text: h?.notes ?? '');
    _assetClass = h?.assetClass ?? 'stock';
    _currency = h?.currency ?? 'COP';
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _avgCostCtrl.dispose();
    _currentPriceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final repo = ref.read(financeRepositoryProvider);
    final data = {
      'account_id': widget.accountId,
      'symbol': _symbolCtrl.text.trim().toUpperCase(),
      'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      'asset_class': _assetClass,
      'currency': _currency,
      'quantity': double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'avg_cost': CurrencyFormatter.parse(_avgCostCtrl.text, currency: _currency),
      'current_price':
          CurrencyFormatter.parse(_currentPriceCtrl.text, currency: _currency),
      'price_updated_at': DateTime.now().toIso8601String(),
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    };

    try {
      if (widget.holding == null) {
        await repo.createHolding(data);
      } else {
        await repo.updateHolding(widget.holding!.id, data);
      }
      ref.invalidate(accountHoldingsProvider(widget.accountId));
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
    final isEdit = widget.holding != null;
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(isEdit ? 'Edit Holding' : 'Add Holding',
                        style: Theme.of(context).textTheme.headlineSmall),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Symbol
                TextFormField(
                  controller: _symbolCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Symbol',
                    border: OutlineInputBorder(),
                    hintText: 'BTC, ETH, VOO, AAPL…',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Bitcoin, Vanguard S&P 500…',
                  ),
                ),
                const SizedBox(height: 12),

                // Asset class
                DropdownButtonFormField<String>(
                  value: _assetClass,
                  decoration: const InputDecoration(
                    labelText: 'Asset Class',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'crypto', child: Text('Crypto')),
                    DropdownMenuItem(value: 'stock', child: Text('Stock')),
                    DropdownMenuItem(value: 'etf', child: Text('ETF')),
                    DropdownMenuItem(value: 'fic', child: Text('FIC / Mutual Fund')),
                    DropdownMenuItem(value: 'bond', child: Text('Bond')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _assetClass = v!),
                ),
                const SizedBox(height: 12),

                // Currency
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'Price Currency',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'COP', child: Text('COP')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                  ],
                  onChanged: (v) => setState(() => _currency = v!),
                ),
                const SizedBox(height: 12),

                // Quantity
                TextFormField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                    hintText: '0.00000000',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Avg cost
                TextFormField(
                  controller: _avgCostCtrl,
                  decoration: InputDecoration(
                    labelText: 'Avg Cost per Unit',
                    prefixText: CurrencyFormatter.prefixFor(_currency),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter(currency: _currency)],
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Current price
                TextFormField(
                  controller: _currentPriceCtrl,
                  decoration: InputDecoration(
                    labelText: 'Current Price per Unit',
                    prefixText: CurrencyFormatter.prefixFor(_currency),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter(currency: _currency)],
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Add Holding'),
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
