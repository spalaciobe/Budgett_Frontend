import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/utils/investment_calculator.dart';
import '../../data/models/account_model.dart';
import '../../data/models/investment_details_model.dart';
import '../../data/repositories/finance_repository.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

/// Dialog to formally record accrued interest on a high-yield savings account.
///
/// Pre-fills the recommended amount using the E.A. compound formula applied to
/// the current balance since [InvestmentDetails.lastInterestDate].
/// On confirm it creates an income transaction and advances [last_interest_date].
class HighYieldInterestDialog extends ConsumerStatefulWidget {
  final Account account;
  final InvestmentDetails details;

  const HighYieldInterestDialog({
    super.key,
    required this.account,
    required this.details,
  });

  @override
  ConsumerState<HighYieldInterestDialog> createState() =>
      _HighYieldInterestDialogState();
}

class _HighYieldInterestDialogState
    extends ConsumerState<HighYieldInterestDialog> {
  late TextEditingController _amountCtrl;
  DateTime _recordDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final recommended = _computeRecommended();
    _amountCtrl = TextEditingController(
      text: CurrencyFormatter.format(recommended, includeSymbol: false),
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double _computeRecommended() {
    final fromDate = widget.details.lastInterestDate;
    if (fromDate == null) return 0;
    return InvestmentCalculator.highYieldAccruedInterest(
      widget.account.balance,
      widget.details.apyRate ?? 0,
      fromDate,
    );
  }

  Future<void> _record() async {
    setState(() => _isLoading = true);
    final amount =
        CurrencyFormatter.parse(_amountCtrl.text, currency: 'COP');
    try {
      await ref.read(financeRepositoryProvider).recordHighYieldInterest(
            accountId: widget.account.id,
            detailsId: widget.details.id,
            amount: amount,
            date: _recordDate,
            currency: 'COP',
            accountName: widget.account.name,
          );
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
    final theme = Theme.of(context);
    final fromDate = widget.details.lastInterestDate;
    final apy = (widget.details.apyRate ?? 0) * 100;
    final days = fromDate != null
        ? DateTime.now().difference(fromDate).inDays
        : null;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Record Interest',
                    style: theme.textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Summary line
            Text(
              '${apy.toStringAsFixed(2)}% E.A. · ${CurrencyFormatter.format(widget.account.balance)} balance'
              '${days != null ? ' · $days days accrued' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.65),
              ),
            ),

            // Period line
            if (fromDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Period: ${DateFormat('MMM d, y').format(fromDate)} → ${DateFormat('MMM d, y').format(_recordDate)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Interest amount field
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Interest to Record',
                prefixText: '\$',
                border: OutlineInputBorder(),
                helperText:
                    'Pre-filled with E.A. compound estimate. Adjust to match your account statement.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [const CurrencyInputFormatter()],
            ),
            const SizedBox(height: 12),

            // Recording date picker
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _recordDate,
                  firstDate: fromDate ?? DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() {
                    _recordDate = picked;
                    // Recompute recommended amount up to the new record date
                    if (fromDate != null) {
                      final updated =
                          InvestmentCalculator.highYieldAccruedInterest(
                        widget.account.balance,
                        widget.details.apyRate ?? 0,
                        fromDate,
                      );
                      _amountCtrl.text = CurrencyFormatter.format(
                          updated,
                          includeSymbol: false);
                    }
                  });
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Recording Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(DateFormat('MMM d, y').format(_recordDate)),
              ),
            ),
            const SizedBox(height: 8),

            // Rate-change tip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'If the APY rate changed, record interest at the old rate first, '
                      'then update the account rate.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _record,
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
