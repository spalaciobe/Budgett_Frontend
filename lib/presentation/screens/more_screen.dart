import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgett_frontend/presentation/navigation/nav_destinations.dart';
import 'package:budgett_frontend/presentation/providers/logout_action.dart';
import 'package:budgett_frontend/presentation/providers/message_capture_provider.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advanced = kNavDestinations.where((d) => !d.showOnMobile).toList();
    // Mobile reaches the capture inbox through this screen, so the pending
    // count is surfaced here rather than on the bottom navigation bar.
    final pendingCaptures =
        ref.watch(pendingCaptureCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ...advanced.map(
              (d) => ListTile(
                leading: Icon(d.selectedIcon),
                title: Text(d.label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (d.path == '/capture-inbox' && pendingCaptures > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Badge(label: Text('$pendingCaptures')),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => context.push(d.path),
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
      ),
    );
  }
}
