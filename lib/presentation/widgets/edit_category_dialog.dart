import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
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
  
  late String _selectedType;
  late String _selectedIcon;
  late String _selectedColor;
  
  bool _isLoading = false;

  final List<String> _colors = [
    '0xFF4CAF50', // Green
    '0xFF2196F3', // Blue
    '0xFFF44336', // Red
    '0xFFFF9800', // Orange
    '0xFF9C27B0', // Purple
    '0xFF673AB7', // Deep Purple
    '0xFF795548', // Brown
    '0xFF009688', // Teal
    '0xFFE91E63', // Pink
    '0xFF607D8B', // Blue Grey
    '0xFF3F51B5', // Indigo
    '0xFF9E9E9E', // Grey
    '0xFF00BCD4', // Cyan
    '0xFFFFC107', // Amber
  ];

  final List<String> _categoryIcons = [
    'home', 'restaurant', 'directions_car', 'health_and_safety', 'bolt', 
    'shopping_cart', 'movie', 'flight', 'school', 'work', 
    'pets', 'fitness_center', 'checkroom', 'credit_card', 'savings', 
    'attach_money', 'card_giftcard', 'smartphone', 'computer', 'build', 
    'palette', 'child_care', 'local_bar', 'music_note', 'subscriptions', 
    'menu_book', 'videogame_asset', 'local_gas_station', 'receipt_long', 'more_horiz'
  ];
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _selectedType = widget.category.type;
    _selectedIcon = widget.category.icon ?? IconHelper.iconMap.keys.first;
    _selectedColor = widget.category.color ?? '0xFF9E9E9E';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
                      SizedBox(
                        height: 50,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _colors.length,
                          itemBuilder: (context, index) {
                            final colorStr = _colors[index];
                            final color = Color(int.parse(colorStr));
                            final isSelected = _selectedColor == colorStr;
                            
                            return GestureDetector(
                              onTap: () => setState(() => _selectedColor = colorStr),
                              child: Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
                                ),
                                child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Icon Picker
                      const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _categoryIcons.length,
                          itemBuilder: (context, index) {
                            final key = _categoryIcons[index];
                            final iconData = IconHelper.getIcon(key);
                            final isSelected = _selectedIcon == key;

                            return InkWell(
                              onTap: () => setState(() => _selectedIcon = key),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : null,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isSelected ? Border.all(color: Theme.of(context).colorScheme.primary) : null,
                                ),
                                child: Icon(
                                  iconData,
                                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                                ),
                              ),
                            );
                          },
                        ),
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
    super.dispose();
  }
}
