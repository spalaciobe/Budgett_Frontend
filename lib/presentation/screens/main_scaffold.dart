import 'package:budgett_frontend/presentation/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final Widget child;
  const MainScaffold({required this.child, super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  bool _isExpanded = false;

  void _toggleSidebar() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _Sidebar(
            isExpanded: _isExpanded,
            onToggle: _toggleSidebar,
          ),
          
          // Main Content
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

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
              height: 64, // Standard AppBar height equivalent
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: isExpanded ? 240 : 80,
                  child: Row(
                    mainAxisAlignment: isExpanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
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
                _SidebarItem(
                   icon: Icons.dashboard,
                   label: 'Home',
                   isSelected: currentPath == '/',
                   isExpanded: isExpanded,
                   onTap: () => context.go('/'),
                ),
                _SidebarItem(
                   icon: Icons.pie_chart,
                   label: 'Budget',
                   isSelected: currentPath == '/budget',
                   isExpanded: isExpanded,
                   onTap: () => context.go('/budget'),
                ),
                _SidebarItem(
                   icon: Icons.flag,
                   label: 'Goals',
                   isSelected: currentPath == '/goals',
                   isExpanded: isExpanded,
                   onTap: () => context.go('/goals'),
                ),
                _SidebarItem(
                   icon: Icons.bar_chart,
                   label: 'Analysis',
                   isSelected: currentPath == '/analysis',
                   isExpanded: isExpanded,
                   onTap: () => context.go('/analysis'),
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(),
                ),

                _SidebarItem(
                   icon: Icons.repeat,
                   label: 'Recurring',
                   isSelected: currentPath == '/recurring',
                   isExpanded: isExpanded,
                   onTap: () => context.go('/recurring'),
                ),
                _SidebarItem(
                   icon: Icons.folder_shared,
                   label: 'Expense Groups',
                   isSelected: currentPath == '/expense-groups',
                   isExpanded: isExpanded,
                   onTap: () => context.go('/expense-groups'),
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(),
                ),

                _SidebarItem(
                   icon: Icons.settings,
                   label: 'Settings',
                   isSelected: currentPath == '/settings',
                   isExpanded: isExpanded,
                   onTap: () => context.go('/settings'),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // User / Logout Section
          InkWell(
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/login');
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: isExpanded ? 240 - 32 : 80 - 32, // Adjust for sidebar item padding
                  child: Row(
                    mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                    mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: theme.colorScheme.secondary,
                        child: Text(
                          user?.email?.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
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
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Logout',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
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
    final color = isSelected ? theme.colorScheme.primary : theme.iconTheme.color?.withOpacity(0.7);
    
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: isExpanded ? 240 - 32 : 80 - 32, // Consistent width for Row
            child: Row(
              mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
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
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
