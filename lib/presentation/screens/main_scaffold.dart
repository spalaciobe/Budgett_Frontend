import 'package:budgett_frontend/core/responsive.dart';
import 'package:budgett_frontend/presentation/navigation/nav_destinations.dart';
import 'package:budgett_frontend/presentation/providers/auth_provider.dart';
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
                tooltip: 'Cerrar sesión',
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
  };

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _selectedIndex(currentPath);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => _onTap(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Presupuesto',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'Más',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  int _selectedIndex(String path) {
    if (path == '/budget') return 1;
    if (_advancedPaths.contains(path)) return 2;
    if (path == '/settings') return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/budget');
      case 2:
        context.go('/more');
      case 3:
        context.go('/settings');
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
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            'Budgett',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
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

            // User / Logout section
            InkWell(
              onTap: () => performLogout(ref, context),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: isExpanded ? 240 - 32 : 80 - 32,
                    child: Row(
                      mainAxisAlignment: isExpanded
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      mainAxisSize:
                          isExpanded ? MainAxisSize.max : MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: theme.colorScheme.secondary,
                          child: Text(
                            user?.email?.substring(0, 1).toUpperCase() ?? 'U',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ),
                        if (isExpanded) ...[
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  user?.email ?? 'User',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Logout',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
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
