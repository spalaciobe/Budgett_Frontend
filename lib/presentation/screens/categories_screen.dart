import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_spacing.dart';
import '../../core/app_theme.dart';
import '../../data/models/category_model.dart';
import '../providers/finance_provider.dart';
import '../utils/icon_helper.dart';
import '../widgets/create_category_dialog.dart';
import '../widgets/edit_category_dialog.dart';
import '../../core/app_text.dart';
import '../widgets/skeleton.dart';
import '../widgets/page_body.dart';
import '../widgets/empty_state.dart';
import '../widgets/screen_title.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: ScreenTitle('Categories'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(categoriesProvider);
          await ref.read(categoriesProvider.future);
        },
        child: categoriesAsync.when(
        loading: () => const SkeletonList(),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (categories) {
          final income = categories.where((c) => c.type == 'income').toList();
          final expense = categories.where((c) => c.type == 'expense').toList();

          // On a fresh account this screen used to render two headings with a
          // count of zero and nothing else — a blank page where the person's
          // first task should be.
          if (categories.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              message:
                  'Categories are how spending gets grouped in your budget. '
                  'Create your first one with the + button.',
            );
          }

          // ContentGrid adds columns as the screen widens and keeps each
          // tile within a readable width, instead of splitting whatever
          // width it is handed between exactly two ~700px tiles.
          Widget section(List<Category> cats) => ContentGrid(
                maxItemWidth: 360,
                spacing: kSpaceLg,
                children: [
                  for (final c in cats) _CategoryTile(category: c, ref: ref),
                ],
              );

          return PageBody(
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: kScreenPadding,
                children: [
                  _SectionHeader(
                    label: 'Income',
                    icon: Icons.arrow_downward,
                    color: context.semantic.positive,
                    count: income.length,
                  ),
                  const SizedBox(height: 8),
                  section(income),
                  kGapXl,
                  _SectionHeader(
                    label: 'Expenses',
                    icon: Icons.arrow_upward,
                    color: Theme.of(context).colorScheme.error,
                    count: expense.length,
                  ),
                  const SizedBox(height: 8),
                  section(expense),
                  const SizedBox(height: 64),
                ],
            ),
          );
        },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const CreateCategoryDialog(),
          );
        },
        tooltip: 'New Category',
        child: const Icon(Icons.add),
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
          label: Text('$count', style: AppText.caption),
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
          backgroundColor: color.withValues(alpha: 0.15),
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
              Tooltip(
                message: 'System category (Colombia)',
                child: Icon(Icons.public, size: 14, color: context.muted),
              ),
          ],
        ),
        subtitle: subCats.isNotEmpty
            ? Text(
                '${subCats.length} sub-categor${subCats.length > 1 ? 'ies' : 'y'}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.muted),
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
                    icon: Icon(Icons.delete_outline, size: 18, color: context.negative),
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
                    leading: Icon(Icons.subdirectory_arrow_right,
                        size: 14, color: context.muted),
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
                FilledButton.styleFrom(backgroundColor: context.negative),
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
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}
