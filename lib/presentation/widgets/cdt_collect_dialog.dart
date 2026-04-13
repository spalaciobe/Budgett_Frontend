import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/investment_calculator.dart';
import '../../data/models/account_model.dart';
import '../../data/repositories/finance_repository.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

/// Dialog to collect a matured CDT: creates the interest income transaction
/// and optionally updates the cash balance.
class CdtCollectDialog extends ConsumerStatefulWidget {
  final Account account;

  const CdtCollectDialog({super.key, required this.account});

  @override
  ConsumerState<CdtCollectDialog> createState() => _CdtCollectDialogState();
}

class _CdtCollectDialogState extends ConsumerState<CdtCollectDialog> {
  late TextEditingController _amountCtrl;
  DateTime _date = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final details = widget.account.investmentDetails;
    final interest = details != null
        ? InvestmentCalculator.cdtAccruedInterest(details)
        : 0.0;
    _amountCtrl = TextEditingController(
      text: CurrencyFormatter.format(interest, includeSymbol: false),
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _collect() async {
    setState(() => _isLoading = true);
    final amount =
        CurrencyFormatter.parse(_amountCtrl.text, currency: 'COP');
    final dateStr =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    try {
      await ref.read(financeRepositoryProvider).addTransaction({
        'account_id': widget.account.id,
        'amount': amount,
        'type': 'income',
        'currency': 'COP',
        'description': 'CDT Interest — ${widget.account.name}',
        'date': dateStr,
        'movement_type': 'income',
      });
      ref.invalidate(accountsProvider);
      ref.invalidate(recentTransactionsProvider);
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
    final details = widget.account.investmentDetails;
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Collect CDT',
                    style: Theme.of(context).textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (details != null) ...[
              Text(
                'Principal: ${CurrencyFormatter.format(details.principal ?? 0)}'
                '\nRate: ${((details.interestRate ?? 0) * 100).toStringAsFixed(2)}% E.A.'
                '\nMaturity: ${details.maturityDate != null ? '${details.maturityDate!.year}-${details.maturityDate!.month.toString().padLeft(2, '0')}-${details.maturityDate!.day.toString().padLeft(2, '0')}' : '—'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.65),
                    ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Interest to Record',
                prefixText: '\$',
                border: OutlineInputBorder(),
                helperText:
                    'Pre-filled with accrued interest. Adjust if needed.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [const CurrencyInputFormatter()],
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
                  labelText: 'Collection Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _collect,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Record Interest'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
