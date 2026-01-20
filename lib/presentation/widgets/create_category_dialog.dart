import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
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
  
  String _selectedType = 'expense';
  String _selectedIcon = 'category';
  String _selectedColor = '0xFF4CAF50'; // Default Green (Hogar)
  
  bool _isLoading = false;

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
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 750),
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
      await repo.addCategory(newCategory);
      
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
    super.dispose();
  }
}
