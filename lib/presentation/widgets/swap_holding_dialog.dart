import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_spacing.dart';
import '../../data/models/investment_holding_model.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

/// Crypto-to-crypto (or stablecoin-to-crypto) swap inside a single investment
/// account. Used to model flows like Wenia's COPW → BTC: quantity leaves the
/// source holding, quantity arrives at the destination holding, an optional
/// commission is recorded on the destination side, and no cash in the account
/// balance is touched.
class SwapHoldingDialog extends ConsumerStatefulWidget {
  final String accountId;
  final List<InvestmentHolding> holdings;

  /// Pre-selected source holding (e.g. if the user tapped "Swap" from the
  /// COPW card). Optional — user can still change it in the dialog.
  final InvestmentHolding? initialSource;

  const SwapHoldingDialog({
    super.key,
    required this.accountId,
    required this.holdings,
    this.initialSource,
  });

  @override
  ConsumerState<SwapHoldingDialog> createState() => _SwapHoldingDialogState();
}

class _SwapHoldingDialogState extends ConsumerState<SwapHoldingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sourceQtyCtrl = TextEditingController();
  final _destQtyCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _descCtrl = TextEditingController(text: 'Swap');

  String? _sourceId;
  String? _destId;
  String? _feeCurrency; // source.currency or dest.currency
  DateTime _date = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final src = widget.initialSource ??
        (widget.holdings.isNotEmpty ? widget.holdings.first : null);
    _sourceId = src?.id;
    // Pre-pick a different holding as destination if available
    final firstOther = widget.holdings
        .where((h) => h.id != _sourceId)
        .cast<InvestmentHolding?>()
        .firstWhere((_) => true, orElse: () => null);
    _destId = firstOther?.id;
    _feeCurrency = firstOther?.currency ?? src?.currency;
  }

  @override
  void dispose() {
    _sourceQtyCtrl.dispose();
    _destQtyCtrl.dispose();
    _feeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  InvestmentHolding? _holdingById(String? id) {
    if (id == null) return null;
    for (final h in widget.holdings) {
      if (h.id == id) return h;
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_sourceId == null || _destId == null) return;
    if (_sourceId == _destId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Source and destination must differ')),
      );
      return;
    }
    setState(() => _isLoading = true);

    final source = _holdingById(_sourceId)!;
    final dest = _holdingById(_destId)!;
    final sourceQty =
        double.tryParse(_sourceQtyCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final destQty =
        double.tryParse(_destQtyCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final fee = _feeCtrl.text.isEmpty
        ? 0.0
        : double.tryParse(_feeCtrl.text.replaceAll(',', '.')) ?? 0.0;

    try {
      await ref.read(financeRepositoryProvider).swapHoldings(
            accountId: widget.accountId,
            sourceHoldingId: source.id,
            destHoldingId: dest.id,
            sourceQty: sourceQty,
            destQty: destQty,
            fee: fee,
            feeCurrency: _feeCurrency,
            date: _date,
            description: _descCtrl.text.trim().isEmpty
                ? 'Swap'
                : _descCtrl.text.trim(),
          );
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
    final source = _holdingById(_sourceId);
    final dest = _holdingById(_destId);
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
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
                        'Swap',
                        style: theme.textTheme.headlineSmall,
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
                  'Moves quantity between two holdings without touching cash. '
                  'Use for COPW → BTC, BTC → ETH, etc.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 16),

                // Source
                DropdownButtonFormField<String>(
                  value: _sourceId,
                  decoration: const InputDecoration(
                    labelText: 'From',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.holdings
                      .map((h) => DropdownMenuItem(
                            value: h.id,
                            child: Text(
                              '${h.symbol}  · ${CurrencyFormatter.formatQuantity(h.quantity)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _sourceId = v;
                    // Dest list filters out the source id; if the user picked
                    // a source that happens to match the current dest, the To
                    // dropdown would have zero items matching _destId and
                    // assert. Re-pick a valid dest.
                    if (_destId == v) {
                      _destId = widget.holdings
                          .firstWhere(
                            (h) => h.id != v,
                            orElse: () => widget.holdings.first,
                          )
                          .id;
                    }
                    _feeCurrency ??= _holdingById(v)?.currency;
                  }),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _sourceQtyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Quantity out',
                    helperText: source == null
                        ? null
                        : 'Available: ${CurrencyFormatter.formatQuantity(source.quantity)} ${source.symbol}',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final q =
                        double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                    if (q <= 0) return 'Must be > 0';
                    if (source != null && q > source.quantity) {
                      return 'Exceeds available';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Destination
                DropdownButtonFormField<String>(
                  value: _destId,
                  decoration: const InputDecoration(
                    labelText: 'To',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.holdings
                      .where((h) => h.id != _sourceId)
                      .map((h) => DropdownMenuItem(
                            value: h.id,
                            child: Text(
                              '${h.symbol}  · ${CurrencyFormatter.formatQuantity(h.quantity)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _destId = v;
                    _feeCurrency = _holdingById(v)?.currency ?? _feeCurrency;
                  }),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _destQtyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Quantity in',
                    helperText: dest == null
                        ? null
                        : 'Received (net of any external fee)  · ${dest.symbol}',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final q =
                        double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                    if (q <= 0) return 'Must be > 0';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Fee — user picks which side's currency the fee is quoted in
                // so we can record it faithfully (Wenia quotes BTC fees on
                // COPW→BTC swaps in BTC).
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _feeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Fee (optional)',
                          border: OutlineInputBorder(),
                          hintText: '0.00000000',
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _feeCurrency,
                        decoration: const InputDecoration(
                          labelText: 'In',
                          border: OutlineInputBorder(),
                        ),
                        items: {
                          source?.currency,
                          dest?.currency,
                          source?.symbol,
                          dest?.symbol,
                        }
                            .whereType<String>()
                            .toSet()
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setState(() => _feeCurrency = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

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
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm Swap'),
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
