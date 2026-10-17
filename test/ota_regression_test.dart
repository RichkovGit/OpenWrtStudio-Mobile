import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/ota_service.dart';

const _downloadBase =
    'https://github.com/RichkovGit/OpenWrtStudio-Mobile/releases/download/v2.6.0/';

Map<String, dynamic> _release(
  String tag,
  List<String> names, {
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'prerelease': prerelease,
  'published_at': '2026-10-17T00:00:00Z',
  'assets': names
      .map(
        (name) => {
          'name': name,
          'browser_download_url': '$_downloadBase$name',
          'size': 4,
        },
      )
      .toList(),
};

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => reply(options);
  @override
  void close({bool force = false}) {}
}

Future<OtaReleaseInfo?> _choose(
  List<Map<String, dynamic>> releases, {
  String? abi = 'arm64-v8a',
  String current = '2.5.22',
}) async {
  final dio = Dio()
    ..httpClientAdapter = _Adapter(
      (_) => ResponseBody.fromString(
        jsonEncode(releases),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
  addTearDown(() => dio.close(force: true));
  return OtaService(
    dio: dio,
    currentVersionProvider: () async => current,
    deviceAbiProvider: () async => abi,
  ).checkForUpdate();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'newer stable version wins over older mobile suffix and preview',
    () async {
      final result = await _choose([
        _release('v2.5.23-mobile', ['app-arm64-v8a-release.apk']),
        _release('v9.0.0', ['app-arm64-v8a-release.apk'], prerelease: true),
        _release('v2.6.0', ['app-arm64-v8a-release.apk']),
      ]);
      expect(result?.version, '2.6.0');
      expect(result?.isPrerelease, isFalse);
    },
  );

  test('x86_64 selects x86_64 APK independently of asset order', () async {
    final result = await _choose([
      _release('v2.6.0', [
        'app-arm64-v8a-release.apk',
        'app-armeabi-v7a-release.apk',
        'app-x86_64-release.apk',
      ]),
    ], abi: 'x86_64');
    expect(result?.apkUrl, endsWith('/app-x86_64-release.apk'));
  });

  test(
    'unsupported device never falls back to an incompatible ARM APK',
    () async {
      expect(
        await _choose([
          _release('v2.6.0', ['app-arm64-v8a-release.apk']),
        ], abi: 'x86'),
        isNull,
      );
    },
  );

  test('unknown device ABI requires a universal APK', () async {
    expect(
      await _choose([
        _release('v2.6.0', ['app-arm64-v8a-release.apk']),
      ], abi: null),
      isNull,
    );
    expect(
      (await _choose([
        _release('v2.6.0', ['app-release.apk']),
      ], abi: null))?.apkUrl,
      endsWith('/app-release.apk'),
    );
  });

  test(
    'malformed versions, old versions and foreign URLs are ignored',
    () async {
      final foreign = _release('v2.6.0', ['app-arm64-v8a-release.apk']);
      (foreign['assets'] as List).single['browser_download_url'] =
          'https://example.com/app.apk';
      expect(
        await _choose([
          foreign,
          _release('v2.5.22', ['app-release.apk']),
          _release('v3.0.0-rc1', ['app-release.apk']),
        ]),
        isNull,
      );
      expect(
        await _choose([
          _release('v2.6.0', ['app-release.apk']),
        ], current: ''),
        isNull,
      );
    },
  );

  test('untrusted URL is rejected without opening the installer', () async {
    final result = await OtaService().downloadAndInstall(
      downloadUrl: 'https://example.com/app.apk',
      version: '2.6.0',
      onProgress: (_, _, _) {},
    );
    expect(result.status, OtaInstallStatus.downloadError);
  });

  for (final valid in [false, true]) {
    test(
      'download ${valid ? 'stages valid ZIP bytes for Android' : 'rejects HTML and removes its staging directory'}',
      () async {
        final parent = await Directory.systemTemp.createTemp('ota-regression-');
        addTearDown(() => parent.delete(recursive: true));
        const channel = MethodChannel('ota-regression');
        String? installedPath;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'getDownloadDir') return parent.path;
              if (call.method == 'installApk') {
                installedPath = (call.arguments as Map)['filePath'] as String;
                return true;
              }
              throw PlatformException(code: 'unexpected');
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final bytes = valid
            ? [0x50, 0x4b, 0x03, 0x04]
            : utf8.encode('<html>download failed</html>');
        final dio = Dio()
          ..httpClientAdapter = _Adapter(
            (_) => ResponseBody.fromBytes(
              bytes,
              200,
              headers: {
                Headers.contentLengthHeader: ['${bytes.length}'],
              },
            ),
          );
        addTearDown(() => dio.close(force: true));
        final result = await OtaService(dio: dio, channel: channel)
            .downloadAndInstall(
              downloadUrl: '${_downloadBase}app-release.apk',
              version: '2.6.0',
              onProgress: (_, _, _) {},
            );
        if (valid) {
          expect(result.status, OtaInstallStatus.success);
          expect(await File(installedPath!).readAsBytes(), bytes);
          expect(File(installedPath!).parent.path, isNot(parent.path));
        } else {
          expect(result.status, OtaInstallStatus.downloadError);
          expect(installedPath, isNull);
          expect(await parent.list().toList(), isEmpty);
        }
      },
    );
  }
}
