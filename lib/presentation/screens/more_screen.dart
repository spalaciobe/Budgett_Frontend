import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/app_text.dart';
import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/presentation/navigation/nav_destinations.dart';
import 'package:budgett_frontend/presentation/providers/logout_action.dart';

import '../widgets/page_body.dart';
import '../widgets/screen_title.dart';

/// What's left once the tasks have somewhere better to live.
///
/// This used to hold seven destinations in a flat list of thin rows: a task
/// (the capture inbox), three planning screens, analysis, categories and
/// settings — most of the app, behind a label that describes none of it. The
/// planning screens are tabs in Plan now and the inbox is a tab in
/// Transactions, so three remain.
///
/// Three rows of 56px would leave four fifths of a phone empty, so they are
/// cards: each one gets its icon, its name and a line saying what it is for.
/// The space is the same; it now carries an explanation.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const _descriptions = {
    '/analysis': 'Cash flow over time and your consolidated portfolio',
    '/categories': 'The buckets your spending is grouped into',
    '/settings': 'Account, capture, notifications and updates',
    '/capture-inbox': 'Every message the capture pipeline has processed',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations =
        kNavDestinations.where((d) => !d.showOnMobile && d.inMore).toList();

    return Scaffold(
      appBar: AppBar(title: ScreenTitle('More')),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kScreenPadding,
        child: PageBody(
          maxWidth: kColumnMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContentGrid(
                maxItemWidth: 260,
                children: [
                  for (final d in destinations)
                    _MoreCard(
                      icon: d.selectedIcon,
                      label: d.label,
                      description: _descriptions[d.path] ?? '',
                      onTap: () => context.push(d.path),
                    ),
                ],
              ),
              kGapBlock,
              OutlinedButton.icon(
                onPressed: () => performLogout(ref, context),
                icon: Icon(Icons.logout, size: 18, color: context.negative),
                label: Text('Log out',
                    style: AppText.cardName.copyWith(color: context.negative)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: context.negative.withValues(alpha: 0.35)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _MoreCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: Padding(
          padding: const EdgeInsets.all(kSpaceXxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              kGapXl,
              Text(label, style: AppText.sectionTitle),
              if (description.isNotEmpty) ...[
                kGapSm,
                Text(
                  description,
                  style: AppText.caption.copyWith(color: context.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
