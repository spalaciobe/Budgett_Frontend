import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category_model.dart';
import '../providers/finance_provider.dart';
import '../utils/icon_helper.dart';
import '../widgets/create_category_dialog.dart';
import '../widgets/edit_category_dialog.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Category',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const CreateCategoryDialog(),
              );
            },
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categories) {
          final income = categories.where((c) => c.type == 'income').toList();
          final expense = categories.where((c) => c.type == 'expense').toList();

          // Separate system (global) categories from user-owned ones
          // System categories have a fixed UUID prefix pattern but we detect them
          // by checking if name comes from the well-known Colombian set.
          // In practice, "user_id" is not exposed in the model; we differentiate
          // by noting system categories are read-only (no delete/edit).

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader(
                label: 'Income',
                icon: Icons.arrow_downward,
                color: Colors.green,
                count: income.length,
              ),
              const SizedBox(height: 8),
              ...income.map((c) => _CategoryTile(category: c, ref: ref)),

              const SizedBox(height: 24),
              _SectionHeader(
                label: 'Expenses',
                icon: Icons.arrow_upward,
                color: Colors.red,
                count: expense.length,
              ),
              const SizedBox(height: 8),
              ...expense.map((c) => _CategoryTile(category: c, ref: ref)),

              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const CreateCategoryDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New Category'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Chip(
          label: Text('$count', style: const TextStyle(fontSize: 12)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final Category category;
  final WidgetRef ref;

  const _CategoryTile({required this.category, required this.ref});

  bool get _isSystemCategory {
    // System categories use the well-known UUID prefix 10000000-0000-0000-0000-...
    return category.id.startsWith('10000000-0000-0000-0000-');
  }

  @override
  Widget build(BuildContext context) {
    final color = category.color != null
        ? Color(int.tryParse(category.color!) ?? 0xFF9E9E9E)
        : const Color(0xFF9E9E9E);
    final iconData = IconHelper.getIcon(category.icon);
    final subCats = category.subCategories ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(iconData, color: color, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                category.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (_isSystemCategory)
              const Tooltip(
                message: 'System category (Colombia)',
                child: Icon(Icons.public, size: 14, color: Colors.blueGrey),
              ),
          ],
        ),
        subtitle: subCats.isNotEmpty
            ? Text(
                '${subCats.length} sub-categor${subCats.length > 1 ? 'ies' : 'y'}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              )
            : null,
        trailing: _isSystemCategory
            ? null // System categories: read-only
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditCategoryDialog(category: category),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(context),
                  ),
                ],
              ),
        children: subCats.isNotEmpty
            ? subCats
                .map(
                  (sc) => ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.only(left: 72, right: 16),
                    title: Text(sc.name,
                        style: Theme.of(context).textTheme.bodySmall),
                    leading: const Icon(Icons.subdirectory_arrow_right,
                        size: 14, color: Colors.grey),
                  ),
                )
                .toList()
            : [],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Delete "${category.name}"? Associated transactions will lose their category.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(financeRepositoryProvider);
      await repo.deleteCategory(category.id);
      ref.invalidate(categoriesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Category "${category.name}" deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e')),
        );
      }
    }
  }
}
