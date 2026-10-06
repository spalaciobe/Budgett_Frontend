/// Reads a receipt photo or a dictated phrase into text, through the native
/// bridge.
///
/// Android-only, like the rest of the capture feature: every entry point
/// returns an empty or negative answer elsewhere rather than throwing, so the
/// UI can be written once and simply not offer the buttons.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Raised when the device could do the job but the attempt failed — no
/// microphone permission, nothing heard, an unreadable image. The message is
/// written to be shown to the user as-is.
class DraftCaptureException implements Exception {
  final String message;
  const DraftCaptureException(this.message);
  @override
  String toString() => message;
}

class DraftCaptureService {
  static const _channel = MethodChannel('budgett/draft_capture');

  const DraftCaptureService();

  /// False on every platform but Android, where the bridge does not exist.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// OCR over an image already on disk.
  ///
  /// Returns the lines in reading order, joined by newlines — the line
  /// structure is not incidental, it is what lets the parsers tell a TOTAL
  /// from a SUBTOTAL and one statement row from the next.
  Future<String> readImage(String path) async {
    if (!isSupported) return '';
    try {
      final text = await _channel.invokeMethod<String>(
        'recognizeText',
        {'path': path},
      );
      return text ?? '';
    } on PlatformException catch (e) {
      throw DraftCaptureException(
        e.message ?? 'Could not read anything from that image',
      );
    }
  }

  /// Whether dictation can be started right now — the recogniser exists and
  /// the microphone is already granted.
  Future<bool> canDictate() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('speechAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Asks for the microphone, returning whether it was granted.
  Future<bool> requestMicrophone() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestMicPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Listens for one phrase and returns what was heard.
  ///
  /// [locale] defaults to Colombian Spanish, which is how this user speaks;
  /// the recogniser falls back to its own default if it has no model for it.
  Future<String> dictate({String locale = 'es-CO'}) async {
    if (!isSupported) return '';
    try {
      final heard = await _channel.invokeMethod<String>(
        'startDictation',
        {'locale': locale},
      );
      return heard ?? '';
    } on PlatformException catch (e) {
      throw DraftCaptureException(e.message ?? 'Could not hear anything');
    }
  }

  /// Abandons a dictation in progress. Safe to call when none is running.
  Future<void> cancelDictation() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancelDictation');
    } on PlatformException {
      // Nothing to cancel is not a failure worth surfacing.
    }
  }
}
