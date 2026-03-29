import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_header.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_constants.dart';
import 'package:budgett_frontend/presentation/widgets/common/icon_picker_grid.dart';
import 'package:budgett_frontend/presentation/widgets/common/color_picker_row.dart';


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
  String _selectedColor = '0xFF4CAF50'; // Default Green

  bool _isLoading = false;
  final List<String> _subCategories = [];

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
              const DialogHeader(title: 'Create Category'),
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
                      ColorPickerRow(
                        colorOptions: kCategoryColors,
                        selectedColor: _selectedColor,
                        onColorSelected: (c) => setState(() => _selectedColor = c),
                      ),
                      const SizedBox(height: 16),

                      // Icon Picker
                      Text('Icon', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: IconPickerGrid(
                          iconOptions: kCategoryIcons,
                          selectedIcon: _selectedIcon,
                          onIconSelected: (k) => setState(() => _selectedIcon = k),
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
