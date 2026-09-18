import 'package:flutter/material.dart';

class NavDestination {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool showOnMobile;

  /// Whether mobile's "More" screen lists this destination. False for the
  /// ones that became tabs elsewhere (Plan's four, Transactions' inbox) —
  /// they keep their routes for deep links and the desktop sidebar, but
  /// listing them twice on a phone is how "More" grew to seven items.
  final bool inMore;
  final bool dividerBefore;

  const NavDestination({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.showOnMobile = false,
    this.inMore = true,
    this.dividerBefore = false,
  });
}

/// Maps any route — including detail routes that aren't themselves nav
/// destinations (e.g. `/credit-card/:id`, `/account/:id`, `/profile`) — to the
/// nav destination path that should read as selected, so the sidebar/rail keep
/// highlighting the right section while on a detail screen.
String navSectionFor(String path) {
  if (path == '/accounts' ||
      path.startsWith('/account/') ||
      path.startsWith('/credit-card/') ||
      path.startsWith('/investment/') ||
      path.startsWith('/pockets/')) {
    return '/accounts';
  }
  if (path == '/profile') return '/settings';
  return path;
}

const kNavDestinations = <NavDestination>[
  NavDestination(
    path: '/',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Transactions',
    showOnMobile: true,
  ),
  NavDestination(
    path: '/accounts',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    label: 'Accounts',
    showOnMobile: true,
  ),
  NavDestination(
    path: '/budget',
    icon: Icons.pie_chart_outline,
    selectedIcon: Icons.pie_chart,
    label: 'Budget',
    showOnMobile: true,
  ),
  NavDestination(
    path: '/goals',
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag,
    label: 'Goals',
    inMore: false,
  ),
  NavDestination(
    path: '/analysis',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart,
    label: 'Analysis',
  ),
  NavDestination(
    path: '/recurring',
    icon: Icons.repeat,
    selectedIcon: Icons.repeat_on,
    label: 'Recurring',
    inMore: false,
    dividerBefore: true,
  ),
  NavDestination(
    path: '/expense-groups',
    icon: Icons.folder_shared_outlined,
    selectedIcon: Icons.folder_shared,
    label: 'Expense Groups',
    inMore: false,
  ),
  NavDestination(
    path: '/capture-inbox',
    icon: Icons.move_to_inbox_outlined,
    selectedIcon: Icons.move_to_inbox,
    // The review queue is a tab in Transactions now, but the history — the
    // audit trail of everything the capture pipeline recorded, deduplicated
    // or dismissed — lives only here. Removing this entry took it with it.
    label: 'Capture history',
  ),
  NavDestination(
    path: '/categories',
    icon: Icons.category_outlined,
    selectedIcon: Icons.category,
    label: 'Categories',
    dividerBefore: true,
  ),
  NavDestination(
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
  ),
];
