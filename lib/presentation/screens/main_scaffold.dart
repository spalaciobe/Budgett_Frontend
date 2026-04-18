import 'package:budgett_frontend/core/responsive.dart';
import 'package:budgett_frontend/presentation/navigation/nav_destinations.dart';
import 'package:budgett_frontend/presentation/providers/auth_provider.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/logout_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ─── Root dispatcher ──────────────────────────────────────────────────────────

class MainScaffold extends ConsumerWidget {
  final Widget child;
  const MainScaffold({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (context.formFactor) {
      case FormFactor.desktop:
        return _DesktopShell(child: child);
      case FormFactor.tablet:
        return _TabletShell(child: child);
      case FormFactor.mobile:
        return _MobileShell(child: child);
    }
  }
}

// ─── Desktop shell (sidebar) ──────────────────────────────────────────────────

class _DesktopShell extends ConsumerStatefulWidget {
  final Widget child;
  const _DesktopShell({required this.child, super.key});

  @override
  ConsumerState<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<_DesktopShell> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            isExpanded: _isExpanded,
            onToggle: () => setState(() => _isExpanded = !_isExpanded),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

// ─── Tablet shell (NavigationRail) ───────────────────────────────────────────

class _TabletShell extends ConsumerWidget {
  final Widget child;
  const _TabletShell({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _selectedIndex(currentPath);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) => context.go(kNavDestinations[i].path),
            labelType: NavigationRailLabelType.selected,
            destinations: kNavDestinations.map((d) {
              return NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: Text(d.label),
              );
            }).toList(),
            trailing: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Log out',
                onPressed: () => performLogout(ref, context),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  int _selectedIndex(String currentPath) {
    final idx = kNavDestinations.indexWhere((d) => d.path == currentPath);
    return idx < 0 ? 0 : idx;
  }
}

// ─── Mobile shell (NavigationBar) ────────────────────────────────────────────

class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child, super.key});

  static const _advancedPaths = {
    '/more',
    '/goals',
    '/analysis',
    '/recurring',
    '/expense-groups',
    '/categories',
    '/settings',
  };

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _selectedIndex(currentPath);
    final router = GoRouter.of(context);

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (currentPath == '/') return false;
        if (router.canPop()) {
          router.pop();
        } else {
          context.go('/');
        }
        return true;
      },
      child: Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => _onTap(context, i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Accounts',
            ),
            NavigationDestination(
              icon: Icon(Icons.pie_chart_outline),
              selectedIcon: Icon(Icons.pie_chart),
              label: 'Budget',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }

  int _selectedIndex(String path) {
    if (path == '/accounts' ||
        path.startsWith('/credit-card/') ||
        path.startsWith('/investment/')) return 1;
    if (path == '/budget') return 2;
    if (_advancedPaths.contains(path)) return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/accounts');
      case 2:
        context.go('/budget');
      case 3:
        context.go('/more');
    }
  }
}

// ─── Sidebar (Desktop) ───────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const _Sidebar({
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final displayName = (profile?.firstName != null)
        ? [profile!.firstName!, profile?.lastName].whereType<String>().join(' ')
        : profile?.username ?? user?.email ?? 'User';
    final displayInitial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : 'U';
    final theme = Theme.of(context);
    final currentPath = GoRouterState.of(context).uri.path;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isExpanded ? 240 : 80,
      color: theme.colorScheme.surface,
      child: ClipRect(
        child: Column(
          children: [
            // Header / Logo area
            SizedBox(
              height: 64,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: isExpanded ? 240 : 80,
                  child: Row(
                    mainAxisAlignment: isExpanded
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.center,
                    children: [
                      if (isExpanded)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/app_icon.png',
                                width: 32,
                                height: 32,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Budgett',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      IconButton(
                        onPressed: onToggle,
                        icon: Icon(isExpanded ? Icons.menu_open : Icons.menu),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final dest in kNavDestinations) ...[
                    if (dest.dividerBefore)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Divider(),
                      ),
                    _SidebarItem(
                      icon: dest.selectedIcon,
                      label: dest.label,
                      isSelected: currentPath == dest.path,
                      isExpanded: isExpanded,
                      onTap: () => context.go(dest.path),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1),

            // User / Profile section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: isExpanded ? 240 - 16 : 80 - 16,
                  child: Row(
                    mainAxisAlignment: isExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    mainAxisSize:
                        isExpanded ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => context.go('/settings'),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: theme.colorScheme.secondary,
                            child: Text(
                              displayInitial,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                      if (isExpanded) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayName,
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          icon: Icon(Icons.logout,
                              color: theme.colorScheme.error),
                          tooltip: 'Log out',
                          onPressed: () => performLogout(ref, context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sidebar item ─────────────────────────────────────────────────────────────

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.iconTheme.color?.withOpacity(0.7);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: isExpanded ? 240 - 32 : 80 - 32,
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 24),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
