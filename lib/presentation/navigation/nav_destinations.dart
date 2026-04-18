import 'package:flutter/material.dart';

class NavDestination {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool showOnMobile;
  final bool dividerBefore;

  const NavDestination({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.showOnMobile = false,
    this.dividerBefore = false,
  });
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
  ),
  NavDestination(
    path: '/analysis',
    icon: Icons.bar_chart,
    selectedIcon: Icons.bar_chart,
    label: 'Analysis',
  ),
  NavDestination(
    path: '/recurring',
    icon: Icons.repeat,
    selectedIcon: Icons.repeat,
    label: 'Recurring',
    dividerBefore: true,
  ),
  NavDestination(
    path: '/expense-groups',
    icon: Icons.folder_shared_outlined,
    selectedIcon: Icons.folder_shared,
    label: 'Expense Groups',
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
