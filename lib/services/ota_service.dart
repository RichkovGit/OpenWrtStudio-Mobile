import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:luci_mobile/utils/logger.dart';

class OtaReleaseInfo {
  final String tagName;
  final String version;
  final String body;
  final String apkUrl;
  final int apkSizeBytes;
  final DateTime publishedAt;
  final bool isPrerelease;

  OtaReleaseInfo({
    required this.tagName,
    required this.version,
    required this.body,
    required this.apkUrl,
    required this.apkSizeBytes,
    required this.publishedAt,
    this.isPrerelease = false,
  });

  String get formattedSize {
    if (apkSizeBytes <= 0) return '';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class OtaService {
  static const MethodChannel _channel = MethodChannel('com.openwrt.studio/notifications');
  static const String repo = 'RichkovGit/OpenWrtStudio-Mobile';
  static const String currentAppVersion = '2.5.6';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'OpenWrtStudio-Mobile-OTA',
      },
    ),
  );

  /// Checks GitHub Releases for updates
  Future<OtaReleaseInfo?> checkForUpdate() async {
    try {
      final response = await _dio.get('https://api.github.com/repos/$repo/releases');
      if (response.statusCode != 200 || response.data is! List) return null;

      final releases = response.data as List;
      if (releases.isEmpty) return null;

      // Filter for mobile release tags
      final latest = releases.firstWhere(
        (r) => (r['tag_name'] ?? '').toString().contains('mobile'),
        orElse: () => releases.first,
      );

      final tagName = (latest['tag_name'] ?? '').toString();
      final body = (latest['body'] ?? '').toString();
      final publishedAtStr = latest['published_at']?.toString() ?? '';
      final publishedAt = DateTime.tryParse(publishedAtStr) ?? DateTime.now();
      final isPrerelease = latest['prerelease'] == true;

      // Extract version: e.g. "v2.5.6-mobile" -> "2.5.6"
      final cleanVersion = _cleanVersion(tagName);

      // Compare with current version
      final currentVer = await getCurrentVersion();
      if (!_isNewerVersion(cleanVersion, currentVer)) {
        return null; // Current is up to date
      }

      // Determine optimal APK asset based on ABI
      String targetAbi = 'arm64';
      try {
        final abi = await _channel.invokeMethod<String>('getDeviceAbi');
        if (abi != null) targetAbi = abi.toLowerCase();
      } catch (_) {}

      final assets = (latest['assets'] as List? ?? []);
      Map<String, dynamic>? selectedAsset;

      // Find best match
      if (targetAbi.contains('arm64') || targetAbi.contains('aarch64')) {
        selectedAsset = assets.firstWhere(
          (a) => (a['name'] ?? '').toString().contains('arm64'),
          orElse: () => null,
        );
      } else if (targetAbi.contains('arm') || targetAbi.contains('v7')) {
        selectedAsset = assets.firstWhere(
          (a) => (a['name'] ?? '').toString().contains('armeabi'),
          orElse: () => null,
        );
      }

      // Fallback to any APK
      selectedAsset ??= assets.firstWhere(
        (a) => (a['name'] ?? '').toString().endsWith('.apk'),
        orElse: () => null,
      );

      if (selectedAsset == null) return null;

      final downloadUrl = selectedAsset['browser_download_url']?.toString() ?? '';
      final sizeBytes = (selectedAsset['size'] as num?)?.toInt() ?? 0;

      return OtaReleaseInfo(
        tagName: tagName,
        version: cleanVersion,
        body: body,
        apkUrl: downloadUrl,
        apkSizeBytes: sizeBytes,
        publishedAt: publishedAt,
        isPrerelease: isPrerelease,
      );
    } catch (e, stack) {
      Logger.error('OTA checkForUpdate error: $e');
      return null;
    }
  }

  /// Downloads APK and initiates Android installation
  Future<bool> downloadAndInstall({
    required String downloadUrl,
    required String version,
    required void Function(double progress, int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      String? dirPath;
      try {
        dirPath = await _channel.invokeMethod<String>('getDownloadDir');
      } catch (_) {}

      dirPath ??= '/sdcard/Download';
      final savePath = '$dirPath/OpenWrtStudio_Mobile_v$version.apk';

      // Delete existing stale download
      final f = File(savePath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }

      await _dio.download(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total).clamp(0.0, 1.0);
            onProgress(progress, received, total);
          }
        },
      );

      // Call native install
      final res = await _channel.invokeMethod<bool>('installApk', {
        'filePath': savePath,
      });

      return res == true;
    } catch (e) {
      Logger.error('OTA downloadAndInstall error: $e');
      return false;
    }
  }

  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version.isNotEmpty ? info.version : currentAppVersion;
    } catch (_) {
      return currentAppVersion;
    }
  }

  static String _cleanVersion(String tag) {
    var s = tag.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[-_]mobile', caseSensitive: false), '');
    return s.trim();
  }

  static bool _isNewerVersion(String latest, String current) {
    try {
      final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (var i = 0; i < 3; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return latest != current;
    }
  }
}
