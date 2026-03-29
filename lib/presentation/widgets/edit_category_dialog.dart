import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_header.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_constants.dart';
import 'package:budgett_frontend/presentation/widgets/common/icon_picker_grid.dart';
import 'package:budgett_frontend/presentation/widgets/common/color_picker_row.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_action_bar.dart';
import 'package:budgett_frontend/presentation/widgets/common/confirm_delete_dialog.dart';


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
              const DialogHeader(title: 'Edit Category'),
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
              DialogActionBar(
                onDelete: _isLoading ? null : _deleteCategory,
                onSave: _isLoading ? null : _updateCategory,
                isLoading: _isLoading,
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
    final confirm = await showConfirmDeleteDialog(
      context,
      title: 'Delete Category?',
      content: 'Are you sure you want to delete "${widget.category.name}"? This cannot be undone and might affect transactions linked to this category.',
    );

    if (!confirm) return;

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
