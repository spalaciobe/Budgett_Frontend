import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/investment_holding_model.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

/// Batch-updates current prices for all holdings in an account.
class UpdatePricesDialog extends ConsumerStatefulWidget {
  final String accountId;
  final List<InvestmentHolding> holdings;

  const UpdatePricesDialog({
    super.key,
    required this.accountId,
    required this.holdings,
  });

  @override
  ConsumerState<UpdatePricesDialog> createState() => _UpdatePricesDialogState();
}

class _UpdatePricesDialogState extends ConsumerState<UpdatePricesDialog> {
  late final List<InvestmentHolding> _priceable;
  late final List<TextEditingController> _controllers;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Cash-equivalents (stablecoins) don't have a meaningful market price to
    // edit — they're pegged 1:1 to their currency. Exclude them here.
    _priceable =
        widget.holdings.where((h) => !h.isCashEquivalent).toList();
    _controllers = _priceable.map((h) {
      return TextEditingController(
        text: CurrencyFormatter.format(
          h.currentPrice,
          currency: h.currency,
          includeSymbol: false,
        ),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    final updates = <({String id, double price})>[];
    for (int i = 0; i < _priceable.length; i++) {
      final price = CurrencyFormatter.parse(
        _controllers[i].text,
        currency: _priceable[i].currency,
      );
      updates.add((id: _priceable[i].id, price: price));
    }

    try {
      await ref
          .read(financeRepositoryProvider)
          .updateHoldingsPrices(updates);
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
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        padding: kDialogPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Update Prices',
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Enter the current market price for each holding.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _priceable.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No priceable holdings — cash-equivalents are pegged to their currency.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                            ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _priceable.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final h = _priceable[i];
                        return Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                h.symbol,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _controllers[i],
                                decoration: InputDecoration(
                                  labelText: h.currency,
                                  prefixText:
                                      CurrencyFormatter.prefixFor(h.currency),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  CurrencyInputFormatter(currency: h.currency),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
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
                    : const Text('Save Prices'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
