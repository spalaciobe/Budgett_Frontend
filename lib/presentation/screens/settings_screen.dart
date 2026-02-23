import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final isDark = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
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
                      ref.read(currencyProvider.notifier).state = c;
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
              ref.read(themeModeProvider.notifier).state = val;
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
    );
  }
}
