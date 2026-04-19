import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
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
  late TextEditingController _sourceSymbolCtrl;
  late String _assetClass;
  late String _currency;
  bool _isCashEquivalent = false;
  bool _isLoading = false;

  // Initial-purchase flow (create mode only).
  bool _recordAsPurchase = false;
  final _feeCtrl = TextEditingController();
  String? _feeCurrency;

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
    _sourceSymbolCtrl = TextEditingController(text: h?.sourceSymbol ?? '');
    _assetClass = h?.assetClass ?? 'stock';
    _currency = h?.currency ?? 'COP';
    _isCashEquivalent = h?.isCashEquivalent ?? false;
    _feeCurrency = _currency;
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _avgCostCtrl.dispose();
    _currentPriceCtrl.dispose();
    _notesCtrl.dispose();
    _sourceSymbolCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final repo = ref.read(financeRepositoryProvider);
    final sourceSymbol = _sourceSymbolCtrl.text.trim();
    final enteredQty =
        double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final enteredPrice =
        CurrencyFormatter.parse(_avgCostCtrl.text, currency: _currency);
    final isCreateWithPurchase =
        widget.holding == null && _recordAsPurchase && enteredQty > 0;

    // When the user opts in to "record as initial purchase", we let
    // buyHolding apply qty/avg_cost through the canonical code path (same one
    // later buys use) and log the expense + fee. The holding row itself is
    // created empty, then immediately filled by buyHolding.
    final data = {
      'account_id': widget.accountId,
      'symbol': _symbolCtrl.text.trim().toUpperCase(),
      'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      'asset_class': _assetClass,
      'currency': _currency,
      'quantity': isCreateWithPurchase ? 0.0 : enteredQty,
      'avg_cost': isCreateWithPurchase ? 0.0 : enteredPrice,
      'current_price':
          CurrencyFormatter.parse(_currentPriceCtrl.text, currency: _currency),
      'price_updated_at': DateTime.now().toIso8601String(),
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'source_symbol': sourceSymbol.isEmpty ? null : sourceSymbol,
      'is_cash_equivalent': _isCashEquivalent,
    };

    try {
      if (widget.holding == null) {
        final created = await repo.createHolding(data);
        if (isCreateWithPurchase) {
          final fee = _feeCtrl.text.isEmpty
              ? 0.0
              : double.tryParse(_feeCtrl.text.replaceAll(',', '.')) ?? 0.0;
          await repo.buyHolding(
            accountId: widget.accountId,
            holdingId: created.id,
            quantity: enteredQty,
            pricePerUnit: enteredPrice,
            fee: fee,
            currency: _currency,
            feeCurrency: _feeCurrency,
            transactionData: {
              'description': 'Buy ${created.symbol} (initial)',
              'date': DateTime.now().toIso8601String().substring(0, 10),
              'movement_type': 'variable',
            },
          );
          ref.invalidate(accountsProvider);
        }
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
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
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
                      child: Text(isEdit ? 'Edit Holding' : 'Add Holding',
                          style: Theme.of(context).textTheme.headlineSmall),
                    ),
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
                const SizedBox(height: 8),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Bitcoin, Vanguard S&P 500…',
                  ),
                ),
                const SizedBox(height: 8),

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
                const SizedBox(height: 8),

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
                const SizedBox(height: 8),

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
                const SizedBox(height: 8),

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
                const SizedBox(height: 8),

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
                const SizedBox(height: 8),

                // Fund Lookup Name (only for FICs) — exact nombre_patrimonio
                // used by the update-prices Edge Function when querying
                // datos.gov.co. If left blank the holding won't auto-update.
                if (_assetClass == 'fic') ...[
                  TextFormField(
                    controller: _sourceSymbolCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Fund Lookup Name (datos.gov.co)',
                      border: OutlineInputBorder(),
                      hintText: 'FIC ABIERTO SIN PACTO DE PERMANENCIA ETF 500 US',
                      helperText:
                          'Exact nombre_patrimonio from datos.gov.co (dataset qhpu-8ixx)',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),

                // Initial-purchase toggle (create mode only). When enabled,
                // the "Avg Cost" field is interpreted as the purchase price
                // per unit, a Fee input appears, and buyHolding is fired
                // after the row is created so the expense + qty/avg_cost land
                // through the same canonical code path as later buys.
                if (!isEdit) ...[
                  SwitchListTile(
                    value: _recordAsPurchase,
                    onChanged: (v) => setState(() => _recordAsPurchase = v),
                    title: const Text('Record as initial purchase'),
                    subtitle: const Text(
                      'Deducts cash from this account and logs the buy as a transaction.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_recordAsPurchase) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _feeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Fee / Commission (optional)',
                              border: OutlineInputBorder(),
                              hintText: '0.00',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _feeCurrency ?? _currency,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'In',
                              border: OutlineInputBorder(),
                            ),
                            items: {
                              _currency,
                              _symbolCtrl.text.trim().toUpperCase(),
                            }
                                .where((s) => s.isNotEmpty)
                                .toSet()
                                .map((c) => DropdownMenuItem(
                                    value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _feeCurrency = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],

                // Cash-equivalent toggle (e.g. COPW stablecoin parked inside
                // an investment account). Holdings flagged here are excluded
                // from P&L / donut / "Invested", but still swap-able.
                SwitchListTile(
                  value: _isCashEquivalent,
                  onChanged: (v) => setState(() => _isCashEquivalent = v),
                  title: const Text('Cash-equivalent (stablecoin)'),
                  subtitle: const Text(
                    'Excluded from P&L and portfolio donut. Use for COPW, USDT, etc.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),

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
