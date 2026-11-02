import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/protocol_item.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/protocol_installer.dart';
import 'package:luci_mobile/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('OpenVPN and Xray aliases are alternatives, not required together', () {
    final list = ProtocolItem.defaultList();
    expect(list.singleWhere((p) => p.id == 'openvpn').installPackageGroups, [
      ['openvpn-openssl', 'openvpn-mbedtls'],
    ]);
    expect(list.singleWhere((p) => p.id == 'xray').installPackageGroups, [
      ['xray-core', 'xray'],
    ]);
  });
  test('background installation polls to a confirmed success', () async {
    final api = _Api(['__OWS_RUNNING__\nfetching', '__OWS_DONE__=0\nverified']);
    final result = await _install(api);
    expect(result.success, isTrue);
    expect(
      api.scripts.first,
      contains('mktemp -d /tmp/openwrt-studio-install.'),
    );
    expect(api.scripts.last, startsWith('rm -rf '));
  });
  test('package error ending in zero is not treated as success', () async {
    final result = await _install(_Api(['__OWS_DONE__=4\nmissing package 10']));
    expect(result.success, isFalse);
    expect(result.message, contains('missing package 10'));
  });
  test('RPC denial cannot submit a successful install', () async {
    final api = _Api([])..denied = true;
    final result = await _install(api);
    expect(result.success, isFalse);
    expect(
      result.error,
      isA<RpcException>().having((e) => e.isAccessDenied, 'denial', true),
    );
    expect(result.mayStillBeRunning, isFalse);
    expect(api.scripts, hasLength(1));
  });
  test(
    'poll timeout reports an uncertain running job and keeps its log',
    () async {
      final api = _Api(['__OWS_RUNNING__\nfetching']);
      final result = await _install(api);
      expect(result.success, isFalse);
      expect(result.message, contains('может продолжаться'));
      expect(api.scripts.any((s) => s.startsWith('rm -rf')), isFalse);
    },
  );
  test('invalid package names never reach file.exec', () async {
    final api = _Api([]);
    final result = await ProtocolInstaller(api).install(
      routerIp: 'router',
      sysauth: 'token',
      useHttps: false,
      groups: [
        ['openvpn; reboot'],
      ],
    );
    expect(result.success, isFalse);
    expect(api.scripts, isEmpty);
  });
}

Future<ProtocolInstallResult> _install(_Api api) =>
    ProtocolInstaller(api, pollInterval: Duration.zero, maxPolls: 2).install(
      routerIp: 'router',
      sysauth: 'token',
      useHttps: false,
      groups: [
        ['openvpn-openssl', 'openvpn-mbedtls'],
      ],
    );

class _Api extends MockApiService {
  final List<String> outputs;
  final scripts = <String>[];
  bool denied = false;
  _Api(this.outputs);
  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    scripts.add(params.last);
    if (denied) return [6];
    String output;
    if (scripts.length == 1) {
      output = 'OWS_JOB=/tmp/openwrt-studio-install.ABC123\n';
    } else if (params.last.startsWith('rm -rf')) {
      output = '';
    } else {
      output = outputs.length > 1 ? outputs.removeAt(0) : outputs.single;
    }
    return [
      0,
      {'code': 0, 'stdout': output},
    ];
  }
}
