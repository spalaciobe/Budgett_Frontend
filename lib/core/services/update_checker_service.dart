import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String latestVersionName;
  final int latestBuildNumber;
  final String currentVersionName;
  final int currentBuildNumber;
  final String apkUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.latestVersionName,
    required this.latestBuildNumber,
    required this.currentVersionName,
    required this.currentBuildNumber,
    required this.apkUrl,
    this.releaseNotes,
  });

  bool get isNewer => latestBuildNumber > currentBuildNumber;
}

class UpdateCheckerService {
  static const _repoOwner = 'spalaciobe';
  static const _repoName = 'Budgett_Frontend';
  static const _latestUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    final res = await http.get(
      Uri.parse(_latestUrl),
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String?) ?? '';
    final parsed = _parseTag(tag);
    if (parsed == null) return null;

    final assets = (data['assets'] as List?) ?? const [];
    final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => (a['name'] as String?)?.endsWith('.apk') ?? false,
          orElse: () => const {},
        );
    final apkUrl = apkAsset['browser_download_url'] as String?;
    if (apkUrl == null) return null;

    final pkg = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(pkg.buildNumber) ?? 0;

    return UpdateInfo(
      latestVersionName: parsed.name,
      latestBuildNumber: parsed.build,
      currentVersionName: pkg.version,
      currentBuildNumber: currentBuild,
      apkUrl: apkUrl,
      releaseNotes: data['body'] as String?,
    );
  }

  // Tag format produced by the release workflow: vX.Y.Z+N
  ({String name, int build})? _parseTag(String tag) {
    final m = RegExp(r'^v?([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$').firstMatch(tag);
    if (m == null) return null;
    return (name: m.group(1)!, build: int.parse(m.group(2)!));
  }
}
