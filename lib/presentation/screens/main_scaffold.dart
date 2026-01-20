import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    // Calculate current index based on location for highlighting
    final String location = GoRouterState.of(context).uri.path;
    int currentIndex = 0;
    if (location.startsWith('/budget')) currentIndex = 1;
    if (location.startsWith('/goals')) currentIndex = 2;
    if (location.startsWith('/analysis')) currentIndex = 3;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0: context.go('/'); break;
            case 1: context.go('/budget'); break;
            case 2: context.go('/goals'); break;
            case 3: context.go('/analysis'); break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.pie_chart), label: 'Budget'),
          NavigationDestination(icon: Icon(Icons.flag), label: 'Goals'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Analysis'),
        ],
      ),
    );
  }
}
