import 'package:flutter/material.dart';

/// An AppBar title that shrinks to fit instead of truncating.
///
/// The screen title is 28px, which is right for "Budget" and too wide for
/// "Recurring Transactions" on a 390dp phone — that one rendered as
/// "Recurring Transacti…", and a truncated heading is worse than a slightly
/// smaller one. Scaling down keeps the whole word; it never scales up, so
/// short titles are untouched.
class ScreenTitle extends StatelessWidget {
  final String text;

  const ScreenTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text),
    );
  }
}
