import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyAsync = ref.watch(currencyProvider);
    final isDarkAsync = ref.watch(themeModeProvider);
    final ccEnabledAsync = ref.watch(ccNotificationsEnabledProvider);
    final ccDaysAsync = ref.watch(ccNotificationDaysBeforeProvider);

    // Derive values with safe fallbacks — no nested when() to avoid full-screen spinners
    final currency = currencyAsync.valueOrNull ?? 'COP';
    final isDark = isDarkAsync.valueOrNull ?? false;
    final ccEnabled = ccEnabledAsync.valueOrNull ?? true;
    final ccDays = ccDaysAsync.valueOrNull ?? 3;
    final isLoading = currencyAsync.isLoading || isDarkAsync.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                        children: ['USD', 'EUR', 'GBP', 'JPY', 'COP', 'MXN']
                            .map(
                              (c) => SimpleDialogOption(
                                onPressed: () {
                                  ref
                                      .read(currencyProvider.notifier)
                                      .setCurrency(c);
                                  Navigator.pop(context);
                                },
                                child: Text(c),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode),
                  title: const Text('Dark Mode'),
                  // Show loading indicator on the trailing side while theme loads
                  value: isDark,
                  onChanged: isDarkAsync.isLoading
                      ? null
                      : (val) {
                          ref
                              .read(themeModeProvider.notifier)
                              .setDarkMode(val);
                        },
                ),
                const Divider(),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Notificaciones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications),
                  title: const Text('Alertas de pago de tarjeta'),
                  subtitle:
                      const Text('Recibe recordatorios antes del vencimiento'),
                  value: ccEnabled,
                  onChanged: ccEnabledAsync.isLoading
                      ? null
                      : (val) {
                          ref
                              .read(ccNotificationsEnabledProvider.notifier)
                              .setEnabled(val);
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Dias de anticipacion'),
                  subtitle: Text('$ccDays dias antes del pago'),
                  onTap: ccDaysAsync.isLoading
                      ? null
                      : () {
                          _showDaysBeforeDialog(context, ref, ccDays);
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

  void _showDaysBeforeDialog(
      BuildContext context, WidgetRef ref, int currentValue) {
    double sliderValue = currentValue.toDouble();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Dias de anticipacion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${sliderValue.round()} dias',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Slider(
                value: sliderValue,
                min: 1,
                max: 30,
                divisions: 29,
                label: '${sliderValue.round()}',
                onChanged: (val) {
                  setState(() => sliderValue = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(ccNotificationDaysBeforeProvider.notifier)
                    .setDaysBefore(sliderValue.round());
                Navigator.pop(context);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
