import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/protocol_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('detached install outlives a short exec call and is later confirmed', () async {
    final directory = await Directory.systemTemp.createTemp('ows-package-test.');
    try {
      final state = File('${directory.path}/state');
      await state.writeAsString('');
      final apk = File('${directory.path}/apk');
      await apk.writeAsString(r'''#!/bin/sh
case "$1" in
update) exit 0;;
info) grep -qx "$3" "$STATE";;
search) echo "$3-1.0";;
add) shift; sleep 2; printf '%s\n' "$@" >> "$STATE";;
esac
''');
      await Process.run('chmod', ['700', apk.path]);
      final api = _ProcessApi(directory.path);
      final result = await ProtocolInstaller(api,
        pollInterval: const Duration(milliseconds: 50), maxPolls: 100,
      ).install(routerIp: 'test-only', sysauth: 'test-only', useHttps: false,
        groups: [['wireguard-tools']]);
      expect(result.success, isTrue, reason: result.message);
      expect(await state.readAsString(), contains('wireguard-tools'));
      expect(api.firstCall, lessThan(const Duration(seconds: 1)));
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
}

class _ProcessApi extends MockApiService {
  final String root;
  Duration? firstCall;
  _ProcessApi(this.root);
  @override
  Future<dynamic> systemExec(String ipAddress, String sysauth, bool useHttps, {
    required String command, List<String> params = const [], BuildContext? context,
  }) async {
    final clock = Stopwatch()..start();
    final result = await Process.run(command, params, environment: {
      'PATH': '$root:/usr/bin:/bin', 'STATE': '$root/state',
    }).timeout(const Duration(seconds: 1));
    firstCall ??= clock.elapsed;
    return [0, {'code': result.exitCode, 'stdout': result.stdout, 'stderr': result.stderr}];
  }
}
