import 'package:flutter/material.dart';
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

  final List<String> _categoryIcons = [
    'home', 'restaurant', 'directions_car', 'health_and_safety', 'bolt', 
    'shopping_cart', 'movie', 'flight', 'school', 'work', 
    'pets', 'fitness_center', 'checkroom', 'credit_card', 'savings', 
    'attach_money', 'card_giftcard', 'smartphone', 'computer', 'build', 
    'palette', 'child_care', 'local_bar', 'music_note', 'subscriptions', 
    'menu_book', 'videogame_asset', 'local_gas_station', 'receipt_long', 'more_horiz',
    'local_cafe', 'medical_services'
  ];
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Create Category', style: Theme.of(context).textTheme.headlineSmall),
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
                        ],
                        selected: {_selectedType},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _selectedType = newSelection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Name Input
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      
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
                      const SizedBox(height: 16),

                      // Icon Picker
                      Text('Icon', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        // No border decoration here as requested
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.start,
                          children: _categoryIcons.map((key) {
                            final iconData = IconHelper.getIcon(key);
                            final isSelected = _selectedIcon == key;
                            
                            return InkWell(
                              onTap: () => setState(() => _selectedIcon = key),
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
                                child: Icon(
                                  iconData,
                                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                                  size: 24,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
                      
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
