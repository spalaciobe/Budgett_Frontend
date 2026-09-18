import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_spacing.dart';
import '../../core/app_text.dart';
import '../utils/currency_formatter.dart';
import '../../core/utils/date_format.dart';

/// The shared pieces of the transaction forms.
///
/// They live here rather than inside one dialog because "Add" and "Edit" are
/// the same form twice, and every other money dialog (paying a card, buying a
/// holding, funding a goal) asks the same first question: how much. When the
/// amount field, the date control and the collapsed section are defined once,
/// a change to the pattern reaches all of them.

/// Income / Expense / Transfer, as a segmented control.
///
/// It goes first in every form that has it: it decides which of the fields
/// below are even relevant, so asking it seventh (as the old dialogs did)
/// meant filling in answers before knowing the question.
class TransactionTypeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const TransactionTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
              value: 'expense',
              label: Text('Expense'),
              icon: Icon(Icons.arrow_outward, size: 15)),
          ButtonSegment(
              value: 'income',
              label: Text('Income'),
              icon: Icon(Icons.south_west, size: 15)),
          ButtonSegment(
              value: 'transfer',
              label: Text('Transfer'),
              icon: Icon(Icons.swap_horiz, size: 15)),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

/// The figure a money form exists to capture, at the size that says so.
///
/// One type size across value, currency mark and placeholder — these used to
/// be 30px, 22px and 13px in the same line, which read as three unrelated
/// things crammed together. The currency mark keeps a trailing space so it
/// sits beside the number rather than glued to it.
class AmountField extends StatelessWidget {
  final TextEditingController controller;

  /// 'COP' or 'USD'. Drives the prefix and the input formatter.
  final String currency;

  final String label;
  final bool enabled;
  final bool autofocus;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  /// Slightly smaller type, for dialogs where the amount shares the screen
  /// with something equally important (a card's balance, a holding's price).
  final bool compact;

  const AmountField({
    super.key,
    required this.controller,
    this.currency = 'COP',
    this.label = 'Amount',
    this.enabled = true,
    this.autofocus = false,
    this.validator,
    this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 22.0 : 28.0;
    final figure = AppText.tabular(size, weight: 700);

    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      style: figure,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [CurrencyInputFormatter(currency: currency)],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${CurrencyFormatter.prefixFor(currency)} ',
        prefixStyle:
            figure.copyWith(color: theme.colorScheme.onSurfaceVariant),
        hintText: '0',
        hintStyle: figure.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 12 : 14),
        border: const OutlineInputBorder(),
      ),
      validator: validator ??
          (value) {
            if (value == null || value.isEmpty) return 'Required';
            if (CurrencyFormatter.parse(value, currency: currency) == 0.0 &&
                value != '0' &&
                value != '0.0') {
              return 'Invalid number';
            }
            return null;
          },
    );
  }
}

/// The date as a control rather than a caption.
///
/// Replaces "Date: 18/09/2026  [Change]" and its cousins — a line of text with
/// a button beside it. Nearly every transaction is entered the day it happened
/// or the day after, so those two are one tap; anything else opens a calendar.
class TransactionDateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const TransactionDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final isToday = _isSameDay(value, today);
    final isYesterday = _isSameDay(value, yesterday);

    return Row(
      children: [
        ChoiceChip(
          label: const Text('Today'),
          selected: isToday,
          onSelected: (_) => onChanged(today),
        ),
        const SizedBox(width: kSpaceLg),
        ChoiceChip(
          label: const Text('Yesterday'),
          selected: isYesterday,
          onSelected: (_) => onChanged(yesterday),
        ),
        const SizedBox(width: kSpaceLg),
        Expanded(
          child: ActionChip(
            avatar: const Icon(Icons.calendar_today, size: 15),
            label: Text(
              isToday || isYesterday
                  ? 'Another day'
                  : formatFullDate(value),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: firstDate ?? DateTime(2000),
                lastDate: lastDate ?? DateTime(2100),
              );
              if (picked != null) onChanged(picked);
            },
          ),
        ),
      ],
    );
  }
}

/// The rarely-used half of a form, collapsed by default.
///
/// Progressive disclosure: the fields that answer "what did I spend?" stay
/// visible, and the ones that answer a question most transactions never ask
/// (is it recurring? does it come out of a sinking fund? is it a
/// reimbursement?) wait behind one tap.
///
/// Pass [initiallyOpen] when editing something that already uses one of the
/// hidden fields — hiding a value someone set earlier is worse than showing a
/// field they don't need.
class MoreOptions extends StatefulWidget {
  final List<Widget> children;
  final bool initiallyOpen;

  const MoreOptions({
    super.key,
    required this.children,
    this.initiallyOpen = false,
  });

  @override
  State<MoreOptions> createState() => _MoreOptionsState();
}

class _MoreOptionsState extends State<MoreOptions> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: primary),
                const SizedBox(width: kSpaceMd),
                Text(
                  _open ? 'Fewer options' : 'More options',
                  style: AppText.cardName.copyWith(color: primary),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.children,
          ),
      ],
    );
  }
}
