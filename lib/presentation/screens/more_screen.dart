import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgett_frontend/presentation/navigation/nav_destinations.dart';
import 'package:budgett_frontend/presentation/providers/logout_action.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advanced = kNavDestinations.where((d) => !d.showOnMobile).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ...advanced.map(
            (d) => ListTile(
              leading: Icon(d.selectedIcon),
              title: Text(d.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(d.path),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () => performLogout(ref, context),
          ),
        ],
      ),
    );
  }
}
