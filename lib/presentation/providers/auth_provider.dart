import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final userProvider = Provider<User?>((ref) {
  final authState = ref.watch(authProvider);
  return authState.value?.session?.user;
});

/// Resolves once Supabase has a session (or confirms there is none).
///
/// Reads that need auth must await this first. Supabase restores the stored
/// token asynchronously, so a provider that queries on its first build can
/// fire before the token is valid; the repositories catch that PGRST303 and
/// then `Future.delayed` for three seconds before retrying. That delay is
/// what made the capture inbox take seconds to appear on a cold start.
///
/// `main.dart` gates `ccAlertSchedulerProvider` the same way.
final sessionReadyProvider = FutureProvider<Session?>((ref) async {
  final current = Supabase.instance.client.auth.currentSession;
  if (current != null) return current;
  // No session yet: wait for the first auth event, which carries one after
  // restoration completes (or null when the user really is signed out).
  final state = await ref.watch(authProvider.future);
  return state.session;
});
