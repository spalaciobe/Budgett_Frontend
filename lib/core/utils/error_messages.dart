import 'package:flutter/foundation.dart';

/// Converts an exception into a short, user-facing message (English, per the
/// UI-copy rule) and logs the raw error for debugging.
///
/// Surfacing the raw `$e` in a Text/SnackBar leaks Postgres/RLS internals and
/// reads like a crash to users — call this instead of interpolating the
/// exception. Detection is by string so it stays import-free and works for
/// Supabase, network, and generic errors alike.
String friendlyError(Object error, {String? action}) {
  debugPrint('[friendlyError]${action != null ? ' [$action]' : ''} $error');

  final type = error.runtimeType.toString().toLowerCase();
  final text = error.toString().toLowerCase();

  if (type.contains('authexception') ||
      text.contains('jwt') ||
      text.contains('not authenticated') ||
      text.contains('invalid login')) {
    return 'Your session has expired. Please sign in again.';
  }

  if (text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection') ||
      text.contains('network is unreachable') ||
      text.contains('timeout')) {
    return 'No connection. Check your internet and try again.';
  }

  if (type.contains('postgrestexception') ||
      text.contains('pgrst') ||
      text.contains('row-level security') ||
      text.contains('violates')) {
    return "We couldn't complete that. Please try again in a moment.";
  }

  return 'Something went wrong. Please try again.';
}
