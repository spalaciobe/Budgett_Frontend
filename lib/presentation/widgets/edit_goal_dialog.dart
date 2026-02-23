import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';

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

  final List<String> _iconOptions = [
    'flag', 'home', 'directions_car', 'flight', 'savings', 'school', 'diamond', 'beach_access',
    'smartphone', 'computer', 'music_note', 'camera_alt', 'fitness_center', 'videogame_asset', 'menu_book', 'palette'
  ];

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _nameController = TextEditingController(text: g.name);
    _targetAmountController = TextEditingController(text: CurrencyFormatter.format(g.targetAmount, includeSymbol: false));
    _currentAmountController = TextEditingController(text: CurrencyFormatter.format(g.currentAmount, includeSymbol: false));
    
    _selectedDeadline = g.deadline;
    // Map emoji to material if necessary, or just use what's there. 
    // If g.iconName is implicitly null or emoji, default to 'flag' or keep it.
    // If it's a valid key in IconHelper, it works.
    _selectedIcon = g.iconName ?? 'flag';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetAmountController.dispose();
    _currentAmountController.dispose();
    super.dispose();
  }

  Future<void> _selectDeadline(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)), // 10 years
    );
    if (picked != null) {
      setState(() {
        _selectedDeadline = picked;
      });
    }
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
      'deadline': _selectedDeadline?.toIso8601String().split('T')[0], // Assuming backend accepts date string
      'icon_name': _selectedIcon,
    };
    
    // Handle specific case where deadline might need to be explicit null if removed (current UI doesn't allow removing deadline easily, but let's be safe)
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Goal?'),
        content: Text('Are you sure you want to delete "${widget.goal.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Edit Goal', style: Theme.of(context).textTheme.headlineSmall),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Icon Selector
                Text('Icon', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _iconOptions.map((icon) {
                    final isSelected = icon == _selectedIcon;
                    return InkWell(
                      onTap: () => setState(() => _selectedIcon = icon),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected 
                              ? Theme.of(context).colorScheme.primary 
                              : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Icon(
                            IconHelper.getIcon(icon),
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                            size: 24,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
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
                TextFormField(
                  controller: _targetAmountController,
                  decoration: const InputDecoration(
                    labelText: 'Target Amount',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter()],
                  onChanged: (_) => setState(() {}), // Recalculate
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (CurrencyFormatter.parse(value) == 0.0 && value != '0' && value != '0.0') return 'Invalid number';
                    return null;
                  },
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
                InkWell(
                  onTap: () => _selectDeadline(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Deadline (optional)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedDeadline != null
                                  ? _selectedDeadline!.toLocal().toString().split(' ')[0]
                                  : 'No deadline set',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                        const Icon(Icons.calendar_today),
                      ],
                    ),
                  ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading ? null : _deleteGoal,
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isLoading ? null : _updateGoal,
                          child: _isLoading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
