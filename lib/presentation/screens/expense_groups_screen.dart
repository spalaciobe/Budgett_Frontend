import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart'; // Ensure this exists or use standard icons
import 'package:budgett_frontend/data/models/expense_group_model.dart';

class ExpenseGroupsScreen extends ConsumerStatefulWidget {
  const ExpenseGroupsScreen({super.key});

  @override
  ConsumerState<ExpenseGroupsScreen> createState() => _ExpenseGroupsScreenState();
}

class _ExpenseGroupsScreenState extends ConsumerState<ExpenseGroupsScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final expenseGroupsAsync = ref.watch(expenseGroupsProvider((month: _selectedDate.month, year: _selectedDate.year)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Groups'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Month Selector
          _buildMonthSelector(),
          
          Expanded(
            child: expenseGroupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return const Center(child: Text('No expense groups for this month.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddGroupDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Theme.of(context).cardColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            onPressed: () {
              setState(() {
                _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1);
              });
            },
          ),
          Text(
            '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            onPressed: () {
              setState(() {
                _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1);
              });
            },
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Future<void> _showAddGroupDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final budgetController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Expense Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g. Paris Trip)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: budgetController,
              decoration: const InputDecoration(labelText: 'Budget Limit', prefixText: '\$'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                final budget = double.tryParse(budgetController.text) ?? 0.0;
                final newGroup = ExpenseGroup(
                  id: '',
                  name: nameController.text,
                  month: _selectedDate.month,
                  year: _selectedDate.year,
                  budgetAmount: budget,
                  icon: 'folder', // Default icon
                );
                
                await ref.read(financeRepositoryProvider).createExpenseGroup(newGroup);
                ref.invalidate(expenseGroupsProvider);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ExpenseGroupCard extends ConsumerWidget {
  final ExpenseGroup group;
  const _ExpenseGroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In a real app we'd fetch actual spending for this group. 
    // For now, we'll placeholder it or need a new specific provider.
    // Let's create a FutureBuilder for group spending inside here to keep it simple self-contained.
    
    return FutureBuilder<List<dynamic>>(
      future: ref.read(financeRepositoryProvider).getTransactionsByGroup(group.id),
      builder: (context, snapshot) {
        double spent = 0;
        if (snapshot.hasData) {
          spent = snapshot.data!.fold(0.0, (sum, t) => sum + t.amount);
        }
        final progress = group.budgetAmount > 0 ? (spent / group.budgetAmount) : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(IconHelper.getIcon(group.icon)),
                        const SizedBox(width: 8),
                        Text(group.name, style: Theme.of(context).textTheme.titleMedium),
                      ],
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
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[200],
                  color: progress > 1 ? Colors.red : Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${CurrencyFormatter.format(spent)} spent'),
                    Text('of ${CurrencyFormatter.format(group.budgetAmount)}'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
