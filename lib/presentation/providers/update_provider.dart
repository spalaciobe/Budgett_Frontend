import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/update_checker_service.dart';

const _kDismissedBuildKey = 'update_dismissed_build';

final updateCheckerServiceProvider = Provider<UpdateCheckerService>((ref) {
  return UpdateCheckerService();
});

/// Resolves to a pending update the user hasn't dismissed yet, or null.
/// Read once at startup; the user can manually re-check from Settings.
final pendingUpdateProvider = FutureProvider<UpdateInfo?>((ref) async {
  final service = ref.read(updateCheckerServiceProvider);
  final info = await service.checkForUpdate();
  if (info == null || !info.isNewer) return null;

  final prefs = await SharedPreferences.getInstance();
  final dismissed = prefs.getInt(_kDismissedBuildKey) ?? 0;
  if (dismissed >= info.latestBuildNumber) return null;

  return info;
});

Future<void> dismissUpdate(int buildNumber) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kDismissedBuildKey, buildNumber);
}
