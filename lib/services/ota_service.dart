import 'dart:io';
import 'package:flutter/foundation.dart';
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

enum OtaInstallStatus {
  success,
  permissionRequired,
  downloadError,
  installError,
}

class OtaInstallResult {
  final OtaInstallStatus status;
  final String? message;

  const OtaInstallResult(this.status, [this.message]);

  bool get isSuccess => status == OtaInstallStatus.success;
}

class OtaService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.openwrt.studio/notifications',
  );
  static const String repo = 'RichkovGit/OpenWrtStudio-Mobile';

  final Dio _dio;
  final MethodChannel _channel;
  final Future<String> Function()? _currentVersionProvider;
  final Future<String?> Function()? _deviceAbiProvider;

  OtaService({
    Dio? dio,
    MethodChannel? channel,
    Future<String> Function()? currentVersionProvider,
    Future<String?> Function()? deviceAbiProvider,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 30),
               headers: {
                 'Accept': 'application/vnd.github.v3+json',
                 'User-Agent': 'OpenWrtStudio-Mobile-OTA',
               },
             ),
           ),
       _channel = channel ?? _defaultChannel,
       _currentVersionProvider = currentVersionProvider,
       _deviceAbiProvider = deviceAbiProvider;

  /// Returns the newest stable release that can actually run on this device.
  Future<OtaReleaseInfo?> checkForUpdate() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final current = _parseVersion(await getCurrentVersion());
      if (current == null) return null;
      final response = await _dio.get(
        'https://api.github.com/repos/$repo/releases',
      );
      if (response.statusCode != 200 || response.data is! List) return null;

      String? abi;
      try {
        abi = _normalizeAbi(
          _deviceAbiProvider != null
              ? await _deviceAbiProvider()
              : await _channel.invokeMethod<String>('getDeviceAbi'),
        );
      } catch (_) {
        /* Only a universal APK is safe when the ABI is unknown. */
      }

      final candidates = <({Map release, List<int> version})>[];
      for (final release in (response.data as List).whereType<Map>()) {
        if (release['draft'] == true || release['prerelease'] == true) continue;
        final version = _parseVersion(release['tag_name']);
        if (version != null && _compareVersions(version, current) > 0) {
          candidates.add((release: release, version: version));
        }
      }
      candidates.sort((a, b) => _compareVersions(b.version, a.version));
      for (final candidate in candidates) {
        final release = candidate.release;
        final rawAssets = release['assets'];
        if (rawAssets is! List) continue;
        final assets = rawAssets.whereType<Map>().where((asset) {
          final name = asset['name'];
          final url = asset['browser_download_url'];
          return name is String &&
              name.toLowerCase().endsWith('.apk') &&
              url is String &&
              _isTrustedApkUrl(url);
        }).toList();
        Map? selected;
        for (final asset in assets) {
          if (abi != null && _assetAbi(asset['name'] as String) == abi) {
            selected = asset;
            break;
          }
        }
        selected ??= assets.cast<Map?>().firstWhere(
          (asset) => _isUniversalApk(asset!['name'] as String),
          orElse: () => null,
        );
        if (selected == null) continue;
        return OtaReleaseInfo(
          tagName: release['tag_name'] as String,
          version: candidate.version.join('.'),
          body: release['body']?.toString() ?? '',
          apkUrl: selected['browser_download_url'] as String,
          apkSizeBytes: selected['size'] is num
              ? (selected['size'] as num).toInt()
              : 0,
          publishedAt:
              DateTime.tryParse(release['published_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
      }
      return null;
    } catch (e) {
      Logger.error('OTA checkForUpdate error: $e');
      return null;
    }
  }

  /// Downloads into a private, unique staging directory before opening Android's installer.
  Future<OtaInstallResult> downloadAndInstall({
    required String downloadUrl,
    required String version,
    required void Function(double progress, int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return const OtaInstallResult(OtaInstallStatus.installError, 'Для Linux используйте AppImage или архив новой версии.');
    Directory? stagingDirectory;
    var keepDownload = false;
    try {
      final parsedVersion = _parseVersion(version);
      if (!_isTrustedApkUrl(downloadUrl) || parsedVersion == null) {
        return const OtaInstallResult(
          OtaInstallStatus.downloadError,
          'Обновления должны быть APK из официального репозитория с корректным номером версии',
        );
      }
      final dirPath = await _channel.invokeMethod<String>('getDownloadDir');
      if (dirPath == null || dirPath.isEmpty) {
        return const OtaInstallResult(
          OtaInstallStatus.downloadError,
          'Не удалось получить папку загрузки приложения',
        );
      }
      final parentDirectory = Directory(dirPath);
      await parentDirectory.create(recursive: true);
      stagingDirectory = await parentDirectory.createTemp('download-');
      final file = File(
        '${stagingDirectory.path}/OpenWrtStudio_Mobile_v${parsedVersion.join('.')}.apk',
      );
      final response = await _dio.download(
        downloadUrl,
        file.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          onProgress(
            total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0,
            received,
            total,
          );
        },
      );
      if (cancelToken?.isCancelled == true) {
        return const OtaInstallResult(
          OtaInstallStatus.downloadError,
          'Загрузка отменена',
        );
      }
      final length = await file.length();
      final expectedLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (length < 4 || (expectedLength != null && expectedLength != length)) {
        return const OtaInstallResult(
          OtaInstallStatus.downloadError,
          'Загруженный файл пуст или загружен не полностью',
        );
      }
      final signature = await file
          .openRead(0, 4)
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
      if (signature.length != 4 ||
          signature[0] != 0x50 ||
          signature[1] != 0x4b ||
          signature[2] != 0x03 ||
          signature[3] != 0x04) {
        return const OtaInstallResult(
          OtaInstallStatus.downloadError,
          'Сервер вернул файл, не соответствующий формату APK',
        );
      }
      try {
        final result = await _channel.invokeMethod<bool>('installApk', {
          'filePath': file.path,
        });
        if (result == true) {
          // Android opens the file asynchronously after the method channel returns.
          keepDownload = true;
          return const OtaInstallResult(OtaInstallStatus.success);
        }
        return const OtaInstallResult(
          OtaInstallStatus.installError,
          'Установщик вернул ошибку запуска',
        );
      } on PlatformException catch (e) {
        if (e.code == 'PERMISSION_DENIED') {
          return const OtaInstallResult(
            OtaInstallStatus.permissionRequired,
            'Разрешите установку приложений из неизвестных источников и повторите установку.',
          );
        }
        return OtaInstallResult(
          OtaInstallStatus.installError,
          e.message ?? 'Ошибка вызова установщика',
        );
      }
    } catch (e) {
      Logger.error('OTA downloadAndInstall error: $e');
      return OtaInstallResult(
        OtaInstallStatus.downloadError,
        'Ошибка загрузки файла: $e',
      );
    } finally {
      if (!keepDownload && stagingDirectory != null) {
        try {
          await stagingDirectory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }

  Future<String> getCurrentVersion() async {
    try {
      final version = _currentVersionProvider != null
          ? await _currentVersionProvider()
          : (await PackageInfo.fromPlatform()).version;
      return _parseVersion(version) == null ? '' : version;
    } catch (_) {
      // An unknown installed version must never be treated as an older release.
      return '';
    }
  }

  static List<int>? _parseVersion(Object? value) {
    if (value is! String) return null;
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:[-_]mobile)?(?:\+\d+)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    final parts = <int>[];
    for (var i = 1; i <= 3; i++) {
      final part = int.tryParse(match.group(i)!);
      if (part == null) return null;
      parts.add(part);
    }
    return parts;
  }

  static int _compareVersions(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      final comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static String? _normalizeAbi(String? abi) => switch (abi?.toLowerCase()) {
    'arm64-v8a' || 'arm64' || 'aarch64' => 'arm64-v8a',
    'armeabi-v7a' || 'armeabi' || 'armv7' || 'armv7l' => 'armeabi-v7a',
    'x86_64' || 'amd64' => 'x86_64',
    'x86' || 'i686' => 'x86',
    _ => null,
  };

  static String? _assetAbi(String name) {
    final lower = name.toLowerCase();
    for (final entry in {
      'arm64-v8a': r'arm64-v8a|arm64|aarch64',
      'armeabi-v7a': r'armeabi-v7a|armeabi|armv7',
      'x86_64': r'x86_64|amd64',
      'x86': r'x86',
    }.entries) {
      if (RegExp('(^|[-_.])(?:${entry.value})([-_.]|\$)').hasMatch(lower)) {
        return entry.key;
      }
    }
    return null;
  }

  static bool _isUniversalApk(String name) {
    final lower = name.toLowerCase();
    return lower == 'app-release.apk' ||
        (_assetAbi(lower) == null &&
            RegExp(r'(^|[-_.])universal([-_.]|$)').hasMatch(lower));
  }

  static bool _isTrustedApkUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final segments = uri.pathSegments;
    return segments.length == 6 &&
        segments[0].toLowerCase() == 'richkovgit' &&
        segments[1].toLowerCase() == 'openwrtstudio-mobile' &&
        segments[2] == 'releases' &&
        segments[3] == 'download' &&
        segments[4].isNotEmpty &&
        segments[5].toLowerCase().endsWith('.apk') &&
        !segments[5].contains('/');
  }
}
