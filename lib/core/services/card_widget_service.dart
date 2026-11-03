/// Feeds the "Best card today" home-screen widget.
///
/// Android-only, like the rest of the native bridges: elsewhere every call is
/// a no-op. The widget renders whatever snapshot was last pushed here — see
/// [buildCardWidgetSnapshot] for why it is a per-day schedule rather than a
/// single answer.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class CardWidgetService {
  static const _channel = MethodChannel('budgett/card_widget');

  const CardWidgetService();

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Stores [snapshot] for the widget and redraws every placed instance.
  Future<void> update(Map<String, dynamic> snapshot) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('update', jsonEncode(snapshot));
    } on PlatformException {
      // A widget that misses one refresh still shows the previous schedule;
      // nothing here is worth interrupting the app for.
    } on MissingPluginException {
      // Engine without the bridge (a background isolate): same reasoning.
    }
  }

  /// Forgets the snapshot, so a signed-out phone does not keep showing the
  /// previous user's cards.
  Future<void> clear() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // See [update].
    } on MissingPluginException {
      // See [update].
    }
  }
}
