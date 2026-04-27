import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';

class ExpenseGroupsScreen extends ConsumerWidget {
  const ExpenseGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseGroupsAsync = ref.watch(expenseGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Groups'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(expenseGroupsProvider);
          await ref.read(expenseGroupsProvider.future);
        },
        child: expenseGroupsAsync.when(
          data: (groups) {
            if (groups.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: const Center(
                      child: Text('No expense groups.\nCreate one with the + button.',
                          textAlign: TextAlign.center),
                    ),
                  ),
                ),
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: kScreenPadding,
              itemCount: groups.length,
              itemBuilder: (context, index) {
                return _ExpenseGroupCard(group: groups[index]);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Error: $e')),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddGroupDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddGroupDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final budgetController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    await showDialog(
      context: context,
      builder: (context) => _AddGroupDialog(
        nameController: nameController,
        budgetController: budgetController,
        onConfirm: (start, end) async {
          startDate = start;
          endDate = end;
        },
      ),
    );

    if (startDate != null && nameController.text.isNotEmpty) {
      final budget = double.tryParse(budgetController.text) ?? 0.0;
      final newGroup = ExpenseGroup(
        id: '',
        name: nameController.text,
        startDate: startDate!,
        endDate: endDate,
        budgetAmount: budget,
        icon: 'folder',
      );
      await ref.read(financeRepositoryProvider).createExpenseGroup(newGroup);
      ref.invalidate(expenseGroupsProvider);
    }
  }
}

/// Separate StatefulWidget so date pickers can update without rebuilding the parent.
class _AddGroupDialog extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController budgetController;
  final Future<void> Function(DateTime start, DateTime? end) onConfirm;

  const _AddGroupDialog({
    required this.nameController,
    required this.budgetController,
    required this.onConfirm,
  });

  @override
  State<_AddGroupDialog> createState() => _AddGroupDialogState();
}

class _AddGroupDialogState extends State<_AddGroupDialog> {
  DateTime? _startDate;
  DateTime? _endDate;

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select';
    return '${date.day} ${_monthAbbr(date.month)} ${date.year}';
  }

  String _monthAbbr(int m) {
    const abbrs = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return abbrs[m - 1];
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        // If end date is now before start date, clear it.
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Expense Group'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g. Trip to Cartagena)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.budgetController,
              decoration: const InputDecoration(
                labelText: 'Budget (optional)',
                prefixText: '\$',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 20),
            const Text('Date Range', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_formatDate(_startDate)),
                    onPressed: _pickStartDate,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_formatDate(_endDate)),
                    onPressed: _pickEndDate,
                  ),
                ),
              ],
            ),
            if (_endDate == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No end date = open group',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _startDate == null || widget.nameController.text.isEmpty
              ? null
              : () async {
                  await widget.onConfirm(_startDate!, _endDate);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ExpenseGroupCard extends ConsumerWidget {
  final ExpenseGroup group;
  const _ExpenseGroupCard({required this.group});

  String _formatDate(DateTime date) {
    const abbrs = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${abbrs[date.month - 1]} ${date.year}';
  }

  String get _dateRangeLabel {
    final start = _formatDate(group.startDate);
    if (group.endDate == null) return '$start → open';
    final end = _formatDate(group.endDate!);
    // Omit year in start if same year as end
    if (group.startDate.year == group.endDate!.year) {
      const abbrs = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final shortStart = '${group.startDate.day} ${abbrs[group.startDate.month - 1]}';
      return '$shortStart → $end';
    }
    return '$start → $end';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<dynamic>>(
      future: ref.read(financeRepositoryProvider).getTransactionsByGroup(group.id),
      builder: (context, snapshot) {
        double spent = 0;
        if (snapshot.hasData) {
          spent = snapshot.data!.fold(0.0, (sum, t) => sum + t.amount);
        }
        final progress = group.budgetAmount > 0 ? (spent / group.budgetAmount) : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: kSpaceLg),
          child: Padding(
            padding: kCardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(IconHelper.getIcon(group.icon)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              group.name,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                      onSelected: (value) async {
                        if (value == 'delete') {
                          await ref.read(financeRepositoryProvider).deleteExpenseGroup(group.id);
                          ref.invalidate(expenseGroupsProvider);
                        }
                      },
                    ),
                  ],
                ),
                kGapSm,
                Text(
                  _dateRangeLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                kGapLg,
                if (group.budgetAmount > 0) ...[
                  LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[200],
                    color: progress > 1 ? Colors.red : Theme.of(context).primaryColor,
                  ),
                  kGapMd,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '${CurrencyFormatter.format(spent)} spent',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'of ${CurrencyFormatter.format(group.budgetAmount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text('${CurrencyFormatter.format(spent)} spent'),
              ],
            ),
          ),
        );
      },
    );
  }
}
