import 'package:flutter/material.dart';

/// Shows a "Discard changes?" confirmation; returns true if the user confirms
/// discarding. Use together with a `PopScope(canPop: false, ...)` so closing a
/// long form (back gesture, barrier tap, or a Close button routed through
/// `Navigator.maybePop`) doesn't silently throw away typed input.
Future<bool> confirmDiscard(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Discard changes?'),
      content: const Text('Your unsaved changes will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return result ?? false;
}
