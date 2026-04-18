import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/utils/investment_calculator.dart';
import '../../data/models/account_model.dart';
import '../../data/models/savings_interest_details_model.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';

/// Dialog to formally record accrued interest on a savings account (parent
/// or pocket). Pre-fills the recommended amount using the E.A. compound
/// formula applied to the current balance since [SavingsInterestDetails.lastInterestDate],
/// correctly accounting for intra-period deposits, withdrawals, and rate changes
/// via [SavingsInterestDetails.periodSegments]. On confirm it creates an income
/// transaction, advances [last_interest_date], and clears [period_segments].
class SavingsInterestDialog extends ConsumerStatefulWidget {
  final Account account;
  final SavingsInterestDetails details;

  const SavingsInterestDialog({
    super.key,
    required this.account,
    required this.details,
  });

  @override
  ConsumerState<SavingsInterestDialog> createState() =>
      _SavingsInterestDialogState();
}

class _SavingsInterestDialogState
    extends ConsumerState<SavingsInterestDialog> {
  late TextEditingController _amountCtrl;
  DateTime _recordDate = DateTime.now();
  bool _isLoading = false;
  bool _showSegmentDetail = false;

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
    return InvestmentCalculator.savingsAccruedInterestWithSegments(
      segments: widget.details.periodSegments,
      currentBalance: widget.account.balance,
      currentApyRate: widget.details.apyRate ?? 0,
      lastInterestDate: fromDate,
    );
  }

  Future<void> _record() async {
    setState(() => _isLoading = true);
    final amount =
        CurrencyFormatter.parse(_amountCtrl.text, currency: 'COP');
    try {
      await ref.read(financeRepositoryProvider).recordSavingsInterest(
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
    final segments = widget.details.periodSegments;
    final hasSegments = segments.isNotEmpty;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: kDialogPadding,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Record Interest',
                        style: theme.textTheme.headlineSmall),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${apy.toStringAsFixed(2)}% E.A. · ${CurrencyFormatter.format(widget.account.balance)} balance'
                '${days != null ? ' · $days days accrued' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
              if (fromDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Period: ${DateFormat('MMM d, y').format(fromDate)} → ${DateFormat('MMM d, y').format(_recordDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
              if (hasSegments) ...[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(
                      () => _showSegmentDetail = !_showSegmentDetail),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_tree_outlined,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${segments.length} balance change${segments.length == 1 ? '' : 's'} tracked — interest calculated per sub-period',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          _showSegmentDetail
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showSegmentDetail) ...[
                  const SizedBox(height: 6),
                  _SegmentBreakdown(
                    segments: segments,
                    currentBalance: widget.account.balance,
                    currentApyRate: widget.details.apyRate ?? 0,
                    lastInterestDate: fromDate!,
                  ),
                ],
              ],
              const SizedBox(height: 10),
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
                      if (fromDate != null) {
                        final updated = InvestmentCalculator
                            .savingsAccruedInterestWithSegments(
                          segments: widget.details.periodSegments,
                          currentBalance: widget.account.balance,
                          currentApyRate: widget.details.apyRate ?? 0,
                          lastInterestDate: fromDate,
                        );
                        _amountCtrl.text = CurrencyFormatter.format(updated,
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
              if (!hasSegments)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer
                        .withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16,
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'If the APY rate changed, record interest at the old rate first, '
                          'then update the account rate.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
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
      ),
    );
  }
}

class _SegmentBreakdown extends StatelessWidget {
  final List<InterestPeriodSegment> segments;
  final double currentBalance;
  final double currentApyRate;
  final DateTime lastInterestDate;

  const _SegmentBreakdown({
    required this.segments,
    required this.currentBalance,
    required this.currentApyRate,
    required this.lastInterestDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.6),
    );
    final valueStyle =
        theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);

    final rows = <_SegmentRow>[];

    for (final seg in segments) {
      final interest = InvestmentCalculator.savingsAccruedInterest(
          seg.balance, seg.apyRate, seg.from,
          toDate: seg.to);
      final days = seg.to
          .difference(
              DateTime(seg.from.year, seg.from.month, seg.from.day))
          .inDays;
      rows.add(_SegmentRow(
        label:
            '${DateFormat('MMM d').format(seg.from)} – ${DateFormat('MMM d').format(seg.to)}',
        balance: seg.balance,
        days: days,
        interest: interest,
        isOpen: false,
      ));
    }

    final openFrom =
        segments.isNotEmpty ? segments.last.to : lastInterestDate;
    final today = DateTime.now();
    final openDays = DateTime(today.year, today.month, today.day)
        .difference(
            DateTime(openFrom.year, openFrom.month, openFrom.day))
        .inDays;
    final openInterest = InvestmentCalculator.savingsAccruedInterest(
        currentBalance, currentApyRate, openFrom);
    rows.add(_SegmentRow(
      label: '${DateFormat('MMM d').format(openFrom)} – today',
      balance: currentBalance,
      days: openDays,
      interest: openInterest,
      isOpen: true,
    ));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(flex: 4, child: Text('Period', style: dimStyle)),
                Expanded(flex: 3, child: Text('Balance', style: dimStyle)),
                Expanded(
                    flex: 2,
                    child: Text('Days',
                        style: dimStyle, textAlign: TextAlign.center)),
                Expanded(
                    flex: 3,
                    child: Text('Interest',
                        style: dimStyle, textAlign: TextAlign.right)),
              ],
            ),
            const Divider(height: 8),
            for (int i = 0; i < rows.length; i++) ...[
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      rows[i].isOpen ? '${rows[i].label} ●' : rows[i].label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: rows[i].isOpen
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      CurrencyFormatter.format(rows[i].balance),
                      style: valueStyle,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${rows[i].days}d',
                      style: dimStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      CurrencyFormatter.format(rows[i].interest),
                      style: valueStyle?.copyWith(
                          color: Colors.green.shade600),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              if (i < rows.length - 1) const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentRow {
  final String label;
  final double balance;
  final int days;
  final double interest;
  final bool isOpen;

  const _SegmentRow({
    required this.label,
    required this.balance,
    required this.days,
    required this.interest,
    required this.isOpen,
  });
}
