import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';


class CreateCategoryDialog extends ConsumerStatefulWidget {
  const CreateCategoryDialog({super.key});

  @override
  ConsumerState<CreateCategoryDialog> createState() => _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends ConsumerState<CreateCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _subCategoryController = TextEditingController();
  
  String _selectedType = 'expense';
  String _selectedIcon = 'category';
  String _selectedColor = '0xFF4CAF50'; // Default Green (Hogar)
  String? _targetAccountId; // savings only — optional physical destination

  bool _isLoading = false;
  final List<String> _subCategories = [];

  final List<String> _colors = [
    '0xFF4CAF50', // Green
    '0xFF2196F3', // Blue
    '0xFFF44336', // Red
    '0xFFFF9800', // Orange
    '0xFF9C27B0', // Purple
    '0xFF009688', // Teal
    '0xFFE91E63', // Pink
    '0xFF3F51B5', // Indigo
    '0xFFFFC107', // Amber
  ];

  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.025,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: kDialogPadding,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text('Create Category', style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type Selector
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.arrow_downward)),
                          ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
                          ButtonSegment(value: 'savings', label: Text('Savings'), icon: Icon(Icons.savings_outlined)),
                        ],
                        selected: {_selectedType},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _selectedType = newSelection.first;
                            if (_selectedType != 'savings') _targetAccountId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 10),

                      // Name Input
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),

                      // Optional destination account for savings categories
                      if (_selectedType == 'savings') ...[
                        savingsTargetAccountField(
                          selectedId: _targetAccountId,
                          onChanged: (id) => setState(() => _targetAccountId = id),
                        ),
                        const SizedBox(height: 10),
                      ],
                      
                      // Color Picker
                      const Text('Color', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Center(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _colors.map((colorStr) {
                            final color = Color(int.parse(colorStr));
                            final isSelected = _selectedColor == colorStr;
                            
                            return GestureDetector(
                              onTap: () => setState(() => _selectedColor = colorStr),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
                                ),
                                child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Icon Picker
                      Text('Icon', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _IconGrid(
                        selectedIcon: _selectedIcon,
                        onSelected: (key) => setState(() => _selectedIcon = key),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
                      
              // Sub Categories
              Text('Sub Categories (Optional)', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _subCategoryController,
                      decoration: const InputDecoration(
                        labelText: 'Add Sub Category',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      if (_subCategoryController.text.isNotEmpty) {
                        setState(() {
                          _subCategories.add(_subCategoryController.text.trim());
                          _subCategoryController.clear();
                        });
                      }
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_subCategories.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _subCategories.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      return ListTile(
                        dense: true,
                        title: Text(_subCategories[index]),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _subCategories.removeAt(index);
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 8),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isLoading ? null : _saveCategory,
                    child: _isLoading 
                       ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                       : const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveCategory() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final newCategory = Category(
        id: '', // Supabase will generate this
        name: _nameController.text.trim(),
        type: _selectedType,
        icon: _selectedIcon,
        color: _selectedColor,
        targetAccountId: _targetAccountId,
      );

      final repo = ref.read(financeRepositoryProvider);
      
      // 1. Add Category
      // We need the ID back from the database to add subcategories.
      // Since addCategory currently doesn't return the ID, we might need to change it, 
      // OR we generate a UUID here if we can (but standard is DB gen).
      // Assuming for now we update addCategory to return the new Category object or ID (checking repo...).
      // Checked repo: addCategory is void. updating logic to fetch the category or assume we can rely on standard "insert and fetch" logic update.
      // For this step, I'll modify the logic to use Supabase's abilities or just make separate calls.
      // Actually, standard practice: repo.createCategory returning the object.
      
      // Workaround without changing repo return type extensively right now:
      // We'll create the category, then fetch the latest one by name/user (risky concurrency) or Update repo first.
      // Let's assume I will update the repo immediately after this to return the ID.
      // For now, I'll write the code assuming `repo.addCategory` returns `Category`. 
      
      // WAIT, I should check FinanceRepository again.
      // It returns Future<void>.
      // I will update this code block to reflect a repo change I will make next.
      final createdCategory = await repo.addCategoryWithReturn(newCategory);

      // 2. Add Sub Categories
      for (final subName in _subCategories) {
        await repo.addSubCategory(SubCategory(
          id: '',
          categoryId: createdCategory.id,
          name: subName,
        ));
      }
      
      // Invalidate Categories provider to refresh list
      ref.invalidate(categoriesProvider);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating category: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _subCategoryController.dispose();
    super.dispose();
  }
}

/// Dropdown of savings/investment accounts (and their pockets) usable as the
/// physical destination of a sinking-fund category. Selection is optional.
/// Shared by [CreateCategoryDialog] and [EditCategoryDialog].
Widget savingsTargetAccountField({
  required String? selectedId,
  required ValueChanged<String?> onChanged,
}) {
  return _SavingsTargetAccountField(
    selectedId: selectedId,
    onChanged: onChanged,
  );
}

class _SavingsTargetAccountField extends ConsumerWidget {
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _SavingsTargetAccountField({
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    return accountsAsync.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => Text('Could not load accounts: $e',
          style: const TextStyle(fontSize: 12, color: Colors.red)),
      data: (accounts) {
        final List<({String id, String label})> options = [];
        for (final a in accounts) {
          if (a.type == 'savings' || a.type == 'investment') {
            options.add((id: a.id, label: a.name));
            for (final p in a.pockets) {
              options.add((id: p.id, label: '${a.name} → ${p.name}'));
            }
          }
        }
        return DropdownButtonFormField<String?>(
          value: selectedId,
          decoration: const InputDecoration(
            labelText: 'Destination account (optional)',
            helperText: 'Where the money physically lives. Purely informational.',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('None')),
            ...options.map((o) => DropdownMenuItem<String?>(
                  value: o.id,
                  child: Text(o.label, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

class _IconGrid extends StatelessWidget {
  final String selectedIcon;
  final ValueChanged<String> onSelected;

  const _IconGrid({required this.selectedIcon, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = MediaQuery.of(context).size.width >= 1024 ? 8 : 6;
        const spacing = 4.0;
        final cellSize = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        final iconSize = (cellSize * 0.48).clamp(14.0, 28.0);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: IconHelper.categoryIconKeys.length,
          itemBuilder: (context, index) {
            final key = IconHelper.categoryIconKeys[index];
            final isSelected = selectedIcon == key;
            return InkWell(
              onTap: () => onSelected(key),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  IconHelper.getIcon(key),
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  size: iconSize,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
