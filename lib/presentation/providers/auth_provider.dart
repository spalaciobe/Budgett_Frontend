import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final userProvider = Provider<User?>((ref) {
  final authState = ref.watch(authProvider);
  return authState.value?.session?.user;
});
