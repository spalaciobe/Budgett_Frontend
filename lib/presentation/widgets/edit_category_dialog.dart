import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';


class EditCategoryDialog extends ConsumerStatefulWidget {
  final Category category;

  const EditCategoryDialog({super.key, required this.category});

  @override
  ConsumerState<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends ConsumerState<EditCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  final _subCategoryController = TextEditingController();
  
  late String _selectedType;
  late String _selectedIcon;
  late String _selectedColor;
  
  bool _isLoading = false;
  
  List<SubCategory> _existingSubCategories = [];
  final List<String> _newSubCategories = [];
  final List<String> _deletedSubCategoryIds = [];

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
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _selectedType = widget.category.type;
    _selectedIcon = widget.category.icon ?? IconHelper.iconMap.keys.first;
    _selectedColor = widget.category.color ?? '0xFF9E9E9E';
    
    if (widget.category.subCategories != null) {
      _existingSubCategories = List.from(widget.category.subCategories!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
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
                  Text('Edit Category', style: Theme.of(context).textTheme.headlineSmall),
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
                      
                      const SizedBox(height: 16),
                      
                      // Sub Categories Management
                      Text('Sub Categories', style: Theme.of(context).textTheme.titleSmall),
                      Column(
                        children: [
                          ..._existingSubCategories.map((sub) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(sub.name),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.grey),
                              onPressed: () {
                                setState(() {
                                  _existingSubCategories.remove(sub);
                                  _deletedSubCategoryIds.add(sub.id);
                                });
                              },
                            ),
                          )),
                          ..._newSubCategories.asMap().entries.map((entry) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.value, style: const TextStyle(fontStyle: FontStyle.italic)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.grey),
                              onPressed: () {
                                setState(() {
                                  _newSubCategories.removeAt(entry.key);
                                });
                              },
                            ),
                          )),
                        ],
                      ),
                      
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
                                  _newSubCategories.add(_subCategoryController.text.trim());
                                  _subCategoryController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   // Delete Button
                  TextButton.icon(
                    onPressed: _isLoading ? null : _deleteCategory,
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                  
                  // Save Buttons
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _isLoading ? null : _updateCategory,
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
    );
  }

  Future<void> _updateCategory() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final categoryData = {
        'name': _nameController.text.trim(),
        'type': _selectedType,
        'icon': _selectedIcon,
        'color': _selectedColor,
      };

      final repo = ref.read(financeRepositoryProvider);
      await repo.updateCategory(widget.category.id, categoryData);
      
      // Handle SubCategories
      
      // 1. Delete removed ones
      for (final id in _deletedSubCategoryIds) {
        await repo.deleteSubCategory(id);
      }
      
      // 2. Add new ones
      for (final name in _newSubCategories) {
        await repo.addSubCategory(SubCategory(
          id: '',
          categoryId: widget.category.id,
          name: name,
        ));
      }
      
      // Invalidate Categories provider to refresh list
      ref.invalidate(categoriesProvider);
      ref.invalidate(budgetsProvider); // Budgets might need visual refresh if color/icon changed
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating category: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteCategory() async {
    // Show confirmation dialog first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Are you sure you want to delete "${widget.category.name}"? This cannot be undone and might affect transactions linked to this category.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    
    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.deleteCategory(widget.category.id);
      
      // Invalidate providers
      ref.invalidate(categoriesProvider);
      ref.invalidate(budgetsProvider);
      
      if (mounted) {
        Navigator.of(context).pop(); // Close edit dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted successfully')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting category: $e')),
        );
      }
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _subCategoryController.dispose();
    super.dispose();
  }
}
