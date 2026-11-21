import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';

/// Client write commands run through a root shell on the router. Anything
/// interpolated into them must be validated first, or a hostile hostname /
/// MAC from the router's own data becomes remote command execution.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingApi api;
  late AppState state;

  setUp(() {
    api = _RecordingApi();
    state = AppState.forTesting(
      apiService: api,
      authService: MockAuthService(),
    );
  });

  const hostileMacs = <String>[
    'aa:bb:cc:dd:ee:ff"; reboot; echo "',
    'aa:bb:cc:dd:ee:ff\$(reboot)',
    'aa:bb:cc:dd:ee:ff;reboot',
    "aa:bb:cc:dd:ee:ff' || reboot || '",
    'not-a-mac',
    '',
    'aa:bb:cc:dd:ee:ff:00',
  ];

  for (final mac in hostileMacs) {
    test('kickClient refuses shell syntax in MAC "$mac"', () async {
      expect(await state.kickClient(mac), isFalse);
      expect(api.executions, isEmpty);
    });
    test('blockClientInternet refuses shell syntax in MAC "$mac"', () async {
      expect(await state.blockClientInternet(mac, true), isFalse);
      expect(await state.blockClientInternet(mac, false), isFalse);
      expect(api.executions, isEmpty);
    });
    test('setStaticLease refuses shell syntax in MAC "$mac"', () async {
      expect(await state.setStaticLease(mac, '192.168.1.50', 'name'), isFalse);
      expect(api.executions, isEmpty);
    });
  }

  test('setStaticLease refuses a non-IPv4 address', () async {
    expect(
      await state.setStaticLease('AA:BB:CC:DD:EE:FF', '1.2.3.4; reboot', 'n'),
      isFalse,
    );
    expect(
      await state.setStaticLease('AA:BB:CC:DD:EE:FF', '999.1.1.1', 'n'),
      isFalse,
    );
    expect(api.executions, isEmpty);
  });

  test('a hostile hostname is sanitized, never executed', () async {
    final ok = await state.setStaticLease(
      'AA:BB:CC:DD:EE:FF',
      '192.168.1.50',
      'evil\$(reboot)"name',
    );
    expect(ok, isTrue);
    final script = api.executions.single.params.last;
    // The payload's substitution is gone; only the sanitized label remains.
    expect(script, isNot(contains('\$(reboot)')));
    expect(script, contains('name="evil__reboot__name"'));
  });

  test('valid client commands still reach the router', () async {
    expect(await state.kickClient('aa:bb:cc:dd:ee:ff'), isTrue);
    expect(api.executions.single.params.last, contains('aa:bb:cc:dd:ee:ff'));
    api.executions.clear();

    expect(await state.blockClientInternet('AA:BB:CC:DD:EE:FF', true), isTrue);
    expect(
      api.executions.single.params.last,
      contains('Block_AA_BB_CC_DD_EE_FF'),
    );
    api.executions.clear();

    expect(
      await state.setStaticLease(
        'AA:BB:CC:DD:EE:FF',
        '192.168.1.50',
        'My Device',
      ),
      isTrue,
    );
    final script = api.executions.single.params.last;
    expect(script, contains('name="My_Device"'));
    expect(script, contains('mac="AA:BB:CC:DD:EE:FF"'));
    expect(script, contains('ip="192.168.1.50"'));
  });
}

class _RecordingApi implements IApiService {
  final executions = <({String ip, String token, List<String> params})>[];

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    executions.add((ip: ipAddress, token: sysauth, params: params));
    return [
      0,
      {'code': 0, 'stdout': ''},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
