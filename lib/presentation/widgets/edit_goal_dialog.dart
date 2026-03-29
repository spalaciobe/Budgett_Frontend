import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_header.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_constants.dart';
import 'package:budgett_frontend/presentation/widgets/common/icon_picker_grid.dart';
import 'package:budgett_frontend/presentation/widgets/common/currency_form_field.dart';
import 'package:budgett_frontend/presentation/widgets/common/date_picker_field.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_action_bar.dart';
import 'package:budgett_frontend/presentation/widgets/common/confirm_delete_dialog.dart';

class EditGoalDialog extends ConsumerStatefulWidget {
  final Goal goal;

  const EditGoalDialog({super.key, required this.goal});

  @override
  ConsumerState<EditGoalDialog> createState() => _EditGoalDialogState();
}

class _EditGoalDialogState extends ConsumerState<EditGoalDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _targetAmountController;
  late TextEditingController _currentAmountController;

  DateTime? _selectedDeadline;
  late String _selectedIcon;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _nameController = TextEditingController(text: g.name);
    _targetAmountController = TextEditingController(text: CurrencyFormatter.format(g.targetAmount, includeSymbol: false));
    _currentAmountController = TextEditingController(text: CurrencyFormatter.format(g.currentAmount, includeSymbol: false));

    _selectedDeadline = g.deadline;
    _selectedIcon = g.iconName ?? 'flag';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetAmountController.dispose();
    _currentAmountController.dispose();
    super.dispose();
  }

  Future<void> _updateGoal() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final goalData = <String, dynamic>{
      'name': _nameController.text,
      'target_amount': CurrencyFormatter.parse(_targetAmountController.text),
      'current_amount': _currentAmountController.text.isEmpty
          ? 0.0
          : CurrencyFormatter.parse(_currentAmountController.text),
      'deadline': _selectedDeadline?.toIso8601String().split('T')[0],
      'icon_name': _selectedIcon,
    };

    if (_selectedDeadline == null) {
      goalData['deadline'] = null;
    }

    try {
      await ref.read(financeRepositoryProvider).updateGoal(widget.goal.id, goalData);

      ref.invalidate(goalsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goal updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteGoal() async {
    final confirm = await showConfirmDeleteDialog(
      context,
      title: 'Delete Goal?',
      content: 'Are you sure you want to delete "${widget.goal.name}"?',
    );

    if (!confirm) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(financeRepositoryProvider).deleteGoal(widget.goal.id);

      ref.invalidate(goalsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goal deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysToDeadline = _selectedDeadline != null
        ? _selectedDeadline!.difference(DateTime.now()).inDays
        : 0;

    final monthsToDeadline = (daysToDeadline / 30).ceil();

    // If deadline is today or passed, or very close, treat as 1 month/immediate for calculation to avoid 0/infinity
    final effectiveMonths = monthsToDeadline <= 0 ? 1 : monthsToDeadline;

    final targetAmount = CurrencyFormatter.parse(_targetAmountController.text);
    final currentAmount = CurrencyFormatter.parse(_currentAmountController.text);
    final remainingAmount = targetAmount - currentAmount;

    final monthlySavings = remainingAmount > 0
        ? remainingAmount / effectiveMonths
        : 0.0;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DialogHeader(title: 'Edit Goal'),
                const SizedBox(height: 24),

                // Icon Selector
                Text('Icon', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                IconPickerGrid(
                  iconOptions: kGoalIconOptions,
                  selectedIcon: _selectedIcon,
                  onIconSelected: (k) => setState(() => _selectedIcon = k),
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Goal Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // Target Amount
                CurrencyFormField(
                  controller: _targetAmountController,
                  labelText: 'Target Amount',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // Current Amount
                TextFormField(
                  controller: _currentAmountController,
                  decoration: const InputDecoration(
                    labelText: 'Current Amount',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                    hintText: '0',
                    helperText: 'Update automatically via transfers or manually here',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter()],
                  onChanged: (_) => setState(() {}), // Recalculate
                ),
                const SizedBox(height: 16),

                // Deadline
                DatePickerField(
                  selectedDate: _selectedDeadline,
                  label: 'Deadline (optional)',
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  onDateSelected: (d) => setState(() => _selectedDeadline = d),
                ),
                const SizedBox(height: 16),

                // Monthly Savings Calculator
                if (_selectedDeadline != null && targetAmount > 0 && remainingAmount > 0)
                  SizedBox(
                    width: double.infinity,
                    child: Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recommended Savings',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${CurrencyFormatter.format(monthlySavings, decimalDigits: 2)} / month',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              'to reach goal by deadline ($monthsToDeadline months left)',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Actions
                DialogActionBar(
                  onDelete: _isLoading ? null : _deleteGoal,
                  onSave: _isLoading ? null : _updateGoal,
                  isLoading: _isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
