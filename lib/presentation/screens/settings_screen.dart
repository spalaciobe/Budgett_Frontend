import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyAsync = ref.watch(currencyProvider);
    final isDarkAsync = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: currencyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (currency) => isDarkAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (isDark) => ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.attach_money),
                title: const Text('Currency'),
                subtitle: Text(currency),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => SimpleDialog(
                      title: const Text('Select Currency'),
                      children: ['USD', 'EUR', 'GBP', 'JPY', 'COP', 'MXN'].map((c) => SimpleDialogOption(
                        onPressed: () {
                          ref.read(currencyProvider.notifier).setCurrency(c);
                          Navigator.pop(context);
                        },
                        child: Text(c),
                      )).toList(),
                    ),
                  );
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode),
                title: const Text('Dark Mode'),
                value: isDark,
                onChanged: (val) {
                  ref.read(themeModeProvider.notifier).setDarkMode(val);
                },
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.info),
                title: Text('About'),
                subtitle: Text('Budgett v1.0.0'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
