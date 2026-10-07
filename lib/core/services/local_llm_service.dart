/// The optional on-device model.
///
/// Weights are not shipped with the app. They are gigabytes, and this APK
/// updates itself over the air from GitHub Releases, so a bundled model would
/// make every release a multi-gigabyte download. Instead the model is fetched
/// once, deliberately, from a settings screen, and everything here answers
/// "not installed" until then.
///
/// Nothing in the app requires it. The rule parsers read a receipt or a
/// dictated phrase on their own; this only runs when they come back unsure,
/// which is the same arrangement the message capture uses — rules decide,
/// the model is the backup.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// A model the user can install.
///
/// Only Gemma 3n is offered: it is the one MediaPipe runs on a phone that
/// also reads images, and at int4 it fits in the memory an app is allowed on
/// a device like an S25 without evicting everything else.
class LocalModelOption {
  final String id;
  final String name;

  /// Roughly, for the confirmation before a long download.
  final int approxBytes;

  /// Where the weights come from. Kept as a field rather than hard-coded so a
  /// model that moves does not need an app release.
  final String url;

  final String description;

  /// Where to accept the licence. Shown because the download cannot work
  /// until the user has, and a 401 says nothing about why.
  final String licencePage;

  const LocalModelOption({
    required this.id,
    required this.name,
    required this.approxBytes,
    required this.url,
    required this.description,
    required this.licencePage,
  });

  String get approxSizeLabel =>
      '${(approxBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// The models offered, smallest first.
const kLocalModels = <LocalModelOption>[
  LocalModelOption(
    id: 'gemma3n-e2b',
    name: 'Gemma 3n E2B',
    approxBytes: 3146000000,
    url: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/'
        'resolve/main/gemma-3n-E2B-it-int4.task',
    description: 'Smaller and quicker. Enough for reading receipts.',
    licencePage: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
  ),
  LocalModelOption(
    id: 'gemma3n-e4b',
    name: 'Gemma 3n E4B',
    approxBytes: 4410000000,
    url: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/'
        'resolve/main/gemma-3n-E4B-it-int4.task',
    description: 'Better at messy text, and noticeably slower.',
    licencePage: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview',
  ),
];

/// Progress of a model download, 0–1, or null while the size is unknown.
typedef DownloadProgress = void Function(double? fraction, int receivedBytes);

class LocalLlmService {
  static const _channel = MethodChannel('budgett/local_llm');

  const LocalLlmService();

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Whether a model is on the device and ready.
  Future<bool> isInstalled() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isInstalled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Bytes the installed model occupies, or 0 when none is installed.
  Future<int> installedSize() async {
    if (!isSupported) return 0;
    try {
      final size = await _channel.invokeMethod<Object?>('sizeBytes');
      return size is int ? size : 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Deletes the model and frees the space.
  Future<void> remove() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('remove');
    } on PlatformException {
      // Nothing installed is not a failure.
    }
  }

  /// Downloads [option] into the place the native side loads from.
  ///
  /// Streamed to a temporary file and moved into place only once complete, so
  /// a download interrupted halfway cannot leave a truncated file that the
  /// runtime would then fail to load with an error about the model rather
  /// than about the download.
  Future<void> download(
    LocalModelOption option, {
    DownloadProgress? onProgress,
    http.Client? client,

    /// A Hugging Face access token. Required: Gemma's weights are gated
    /// behind Google's licence, and without one the download is a 401.
    String? token,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('A local model only runs on Android');
    }

    final destination = await _channel.invokeMethod<String>('modelPath');
    if (destination == null) {
      throw StateError('The native side gave no place to put the model');
    }
    // Unload first: the runtime holds the file open once it has loaded it.
    await _channel.invokeMethod<void>('unload');

    final httpClient = client ?? http.Client();
    final partial = File('$destination.part');
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(option.url));
      // Gemma's weights sit behind Google's licence on Hugging Face, so an
      // anonymous GET is refused. The token is sent to huggingface.co and
      // nowhere else.
      if (token != null && token.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${token.trim()}';
      }
      // Hugging Face answers with a redirect to a CDN; following it by hand
      // would drop the header, and dropping it is a 401 on the second hop.
      request.followRedirects = true;
      final response = await httpClient.send(request);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const LocalLlmUnavailable(
          'Hugging Face refused the download. These weights are gated: open '
          'the model page in a browser, accept Google\'s licence, then paste '
          'an access token below.',
        );
      }
      if (response.statusCode != 200) {
        throw HttpException(
          'The download failed (HTTP ${response.statusCode})',
          uri: Uri.parse(option.url),
        );
      }

      final total = response.contentLength;
      var received = 0;
      sink = partial.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null ? null : received / total, received);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      await partial.rename(destination);
    } catch (_) {
      await sink?.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Runs [prompt] through the installed model.
  ///
  /// Throws when no model is installed, which the caller treats as "no
  /// fallback available" rather than as an error worth showing.
  Future<String> generate(String prompt) async {
    if (!isSupported) {
      throw const LocalLlmUnavailable('A local model only runs on Android');
    }
    try {
      final answer = await _channel.invokeMethod<String>(
        'generate',
        {'prompt': prompt},
      );
      return answer ?? '';
    } on PlatformException catch (e) {
      if (e.code == 'not_installed') {
        throw const LocalLlmUnavailable('No local model is installed');
      }
      throw LocalLlmUnavailable(e.message ?? 'The local model failed');
    }
  }
}

/// The model cannot answer — not installed, not supported, or it failed to
/// load. Always recoverable: the caller falls back to what the rules read.
class LocalLlmUnavailable implements Exception {
  final String message;
  const LocalLlmUnavailable(this.message);
  @override
  String toString() => message;
}
