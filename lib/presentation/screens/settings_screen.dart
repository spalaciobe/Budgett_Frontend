import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgett_frontend/core/services/update_checker_service.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';
import 'package:budgett_frontend/presentation/providers/logout_action.dart';
import 'package:budgett_frontend/presentation/providers/fx_rate_provider.dart';
import 'package:budgett_frontend/presentation/providers/update_provider.dart';
import 'package:budgett_frontend/presentation/widgets/update_available_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyAsync = ref.watch(currencyProvider);
    final isDarkAsync = ref.watch(themeModeProvider);
    final ccEnabledAsync = ref.watch(ccNotificationsEnabledProvider);
    final ccDaysAsync = ref.watch(ccNotificationDaysBeforeProvider);
    final fxAsync = ref.watch(fxRateProvider);

    // Derive values with safe fallbacks — no nested when() to avoid full-screen spinners
    final currency = currencyAsync.valueOrNull ?? 'COP';
    final isDark = isDarkAsync.valueOrNull ?? (MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final ccEnabled = ccEnabledAsync.valueOrNull ?? true;
    final ccDays = ccDaysAsync.valueOrNull ?? 3;
    final isLoading = currencyAsync.isLoading || isDarkAsync.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(fxRateProvider);
                await ref.read(fxRateProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                    'Notifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications),
                  title: const Text('Credit Card Payment Alerts'),
                  subtitle:
                      const Text('Receive reminders before payment due date'),
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
                  title: const Text('Days in advance'),
                  subtitle: Text('$ccDays days before payment'),
                  onTap: ccDaysAsync.isLoading
                      ? null
                      : () {
                          _showDaysBeforeDialog(context, ref, ccDays);
                        },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Exchange Rate',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                fxAsync.when(
                  loading: () => const ListTile(
                    leading: Icon(Icons.currency_exchange),
                    title: Text('TRM (USD → COP)'),
                    subtitle: Text('Loading…'),
                  ),
                  error: (_, __) => const ListTile(
                    leading: Icon(Icons.currency_exchange),
                    title: Text('TRM (USD → COP)'),
                    subtitle: Text('Unavailable'),
                  ),
                  data: (fxRate) {
                    if (fxRate == null) {
                      return const ListTile(
                        leading: Icon(Icons.currency_exchange),
                        title: Text('TRM (USD → COP)'),
                        subtitle: Text('Unavailable'),
                      );
                    }
                    final dateStr = DateFormat('d MMM yyyy', 'en').format(fxRate.asOfDate);
                    final rateStr = NumberFormat('#,##0.00', 'en_US').format(fxRate.rate);
                    return ListTile(
                      leading: const Icon(Icons.currency_exchange),
                      title: Text('\$$rateStr COP'),
                      subtitle: Text(
                        '${fxRate.isStale ? "Stale — " : ""}As of $dateStr · ${fxRate.source}',
                      ),
                      trailing: fxRate.isStale
                          ? Tooltip(
                              message: 'Could not fetch today\'s rate — using last cached value',
                              child: Icon(Icons.warning_amber_rounded,
                                  color: Theme.of(context).colorScheme.error),
                            )
                          : null,
                    );
                  },
                ),
                const Divider(),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Account',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Edit profile'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/profile'),
                ),
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text('Check for updates'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _checkForUpdates(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Log out'),
                  onTap: () => performLogout(ref, context),
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
    );
  }

  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Checking for updates…'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final info = await ref.read(updateCheckerServiceProvider).checkForUpdate();
      if (!context.mounted) return;
      if (info == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Updates only available on Android.')),
        );
        return;
      }
      if (!info.isNewer) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'You are on the latest version (${info.currentVersionName}+${info.currentBuildNumber}).',
            ),
          ),
        );
        return;
      }
      ref.invalidate(pendingUpdateProvider);
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateAvailableDialog(info: info),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Update check failed: $e')),
      );
    }
  }

  void _showDaysBeforeDialog(
      BuildContext context, WidgetRef ref, int currentValue) {
    double sliderValue = currentValue.toDouble();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Days in advance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${sliderValue.round()} days',
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
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(ccNotificationDaysBeforeProvider.notifier)
                    .setDaysBefore(sliderValue.round());
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
