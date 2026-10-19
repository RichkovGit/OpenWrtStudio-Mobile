import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/usb_models.dart';
import 'package:luci_mobile/screens/usb_config_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/usb_config_service.dart';
import 'package:luci_mobile/state/app_state.dart';

void main() {
  test(
    'mount updates the selected UUID and preserves other fstab settings',
    () async {
      final api = _UsbApi();
      api.configs['fstab'] = {
        'global': {'.type': 'global', 'anon_mount': '0'},
        'extroot': {
          '.type': 'mount',
          'uuid': 'ROOT',
          'target': '/overlay',
          'enabled': '1',
        },
        'selected': {
          '.type': 'mount',
          'uuid': 'USB',
          'target': '/mnt/old',
          'options': 'ro,noatime',
          'custom': 'keep',
        },
        'last': {
          '.type': 'mount',
          'uuid': 'OTHER',
          'target': '/mnt/other',
          'enabled': '1',
        },
      };
      final before = _snapshot(api.configs['fstab']!);
      final service = UsbConfigService(apiService: api);

      expect(
        await service.mountDisk(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          deviceNode: '/dev/sdb1',
          mountPoint: '/mnt/data',
          fileSystem: 'ext4',
        ),
        isTrue,
      );

      final expected = _snapshot(before);
      expected['selected']!['target'] = '/mnt/data';
      expected['selected']!['enabled'] = '1';
      expect(api.configs['fstab'], expected);
      expect(api.addedConfigs, isEmpty);
      expect(api.committedConfigs, ['fstab']);
    },
  );

  test('a new mount adds only its own UUID entry', () async {
    final api = _UsbApi();
    api.configs['fstab'] = {
      'global': {'.type': 'global', 'auto_mount': '0'},
      'extroot': {'.type': 'mount', 'uuid': 'ROOT', 'target': '/overlay'},
    };
    final service = UsbConfigService(apiService: api);
    expect(
      await service.mountDisk(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        deviceNode: '/dev/sdb1',
        mountPoint: '/mnt/data',
        fileSystem: 'exfat',
      ),
      isTrue,
    );
    expect(api.configs['fstab']!['global'], {
      '.type': 'global',
      'auto_mount': '0',
    });
    expect(api.configs['fstab']!['extroot'], {
      '.type': 'mount',
      'uuid': 'ROOT',
      'target': '/overlay',
    });
    expect(api.configs['fstab']!['cfg1'], {
      '.type': 'mount',
      'uuid': 'USB',
      'target': '/mnt/data',
      'enabled': '1',
      'options': 'rw,noatime',
    });
  });

  test('mount refuses an extroot device and an occupied target', () async {
    for (final existing in [
      {'.type': 'mount', 'uuid': 'USB', 'target': '/overlay/'},
      {'.type': 'mount', 'uuid': 'OTHER', 'target': '/mnt/data'},
    ]) {
      final api = _UsbApi();
      api.configs['fstab'] = {'existing': existing};
      final before = _snapshot(api.configs['fstab']!);
      expect(
        await UsbConfigService(apiService: api).mountDisk(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          deviceNode: '/dev/sdb1',
          mountPoint: '/mnt/data',
        ),
        isFalse,
      );
      expect(api.configs['fstab'], before);
      expect(
        api.scripts.where((script) => script.startsWith('mkdir -p')),
        isEmpty,
      );
      expect(api.committedConfigs, isEmpty);
    }
  });

  test(
    'modem values round trip without shell evaluation or lost credentials',
    () async {
      final api = _UsbApi();
      api.configs['network'] = {
        'lan': {'.type': 'interface', 'proto': 'static'},
        'wwan': {'.type': 'interface', 'metric': '42', 'custom': 'keep'},
      };
      final service = UsbConfigService(apiService: api);
      const profile = UsbModemProfile(
        apn: "isp'; echo injected; '",
        pinCode: '1234',
        authType: 'pap',
        username: "user='quoted'",
        password: r"pass'=$()\secret",
      );
      expect(
        await service.saveModemProfile(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          profile: profile,
        ),
        isTrue,
      );
      expect(api.scripts, isEmpty);
      expect(api.configs['network']!['wwan']!['metric'], '42');
      expect(api.configs['network']!['wwan']!['custom'], 'keep');
      expect(api.configs['network']!['lan'], {
        '.type': 'interface',
        'proto': 'static',
      });

      final loaded = await service.getModemProfile(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
      );
      expect(loaded.apn, profile.apn);
      expect(loaded.pinCode, '1234');
      expect(loaded.username, profile.username);
      expect(loaded.password, profile.password);
      expect(loaded.isUp, isTrue);
      expect(loaded.ipAddress, '10.0.0.2');
    },
  );

  test('new modem profile uses a named interface section', () async {
    final api = _UsbApi();
    expect(
      await UsbConfigService(apiService: api).saveModemProfile(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        profile: const UsbModemProfile(
          pinCode: '1234',
          username: 'user',
          password: 'pass',
        ),
      ),
      isTrue,
    );
    expect(api.configs['network']!['wwan']!['.type'], 'interface');
    expect(api.configs['network']!['wwan']!['pincode'], '1234');
    expect(api.configs['network']!['wwan']!['username'], 'user');
    expect(api.configs['network']!['wwan']!['password'], 'pass');
  });

  test('invalid modem identifiers and PINs do not reach the router', () async {
    final api = _UsbApi();
    final service = UsbConfigService(apiService: api);
    for (final profile in const [
      UsbModemProfile(interfaceName: 'wwan;reboot'),
      UsbModemProfile(deviceNode: '/dev/../etc/passwd'),
      UsbModemProfile(deviceNode: '/dev/cdc-wdm0;reboot'),
      UsbModemProfile(pinCode: '12'),
      UsbModemProfile(apn: 'bad\nvalue'),
    ]) {
      expect(
        await service.saveModemProfile(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          profile: profile,
        ),
        isFalse,
      );
    }
    expect(
      await service.restartModemInterface(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        interfaceName: 'wwan;reboot',
      ),
      isFalse,
    );
    expect(api.readConfigs, isEmpty);
    expect(api.scripts, isEmpty);
  });

  test(
    'new Samba shares use samba4 UCI and failures do not report success',
    () async {
      final api = _UsbApi();
      final service = UsbConfigService(apiService: api);
      expect(
        await service.enableSamba(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          path: "/mnt/O'Brien",
          shareName: "O'Brien",
        ),
        isTrue,
      );
      expect(api.addedConfigs, ['samba4']);
      expect(api.configs['samba4']!['cfg1']!['.type'], 'sambashare');
      expect(api.configs['samba4']!['cfg1']!['path'], "/mnt/O'Brien");
      expect(api.configs['samba4']!['cfg1']!['name'], "O'Brien");

      final failedApi = _UsbApi()..failWrites = true;
      expect(
        await UsbConfigService(apiService: failedApi).enableSamba(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          path: '/mnt/data',
        ),
        isFalse,
      );
      expect(failedApi.scripts, isEmpty);
      expect(failedApi.committedConfigs, isEmpty);
    },
  );

  test('existing Samba share retains its access controls and name', () async {
    final api = _UsbApi();
    api.configs['samba4'] = {
      'private': {
        '.type': 'sambashare',
        'path': '/mnt/data',
        'name': 'Private',
        'guest_ok': 'no',
        'users': 'alice',
        'read_only': 'yes',
      },
      'other': {
        '.type': 'sambashare',
        'path': '/mnt/database',
        'name': 'Other',
      },
    };
    final before = _snapshot(api.configs['samba4']!);
    expect(
      await UsbConfigService(apiService: api).enableSamba(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        path: '/mnt/data',
      ),
      isTrue,
    );
    expect(api.configs['samba4'], before);
    expect(api.addedConfigs, isEmpty);
  });

  test('Samba restart and modem commit failures are visible', () async {
    final restartApi = _UsbApi()..failExec = true;
    expect(
      await UsbConfigService(apiService: restartApi).enableSamba(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        path: '/mnt/data',
      ),
      isFalse,
    );
    final commitApi = _UsbApi()..failCommit = true;
    expect(
      await UsbConfigService(apiService: commitApi).saveModemProfile(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        profile: const UsbModemProfile(),
      ),
      isFalse,
    );
  });

  testWidgets('USB loading may finish after its screen is closed', (
    tester,
  ) async {
    final service = _DelayedUsbService();
    final state = _UsbAppState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: MaterialApp(home: UsbConfigScreen(service: service)),
      ),
    );
    await tester.pump();
    expect(service.profileRequested, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    service.profile.complete(const UsbModemProfile(apn: 'late-result'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Map<String, Map<String, dynamic>> _snapshot(
  Map<String, Map<String, dynamic>> source,
) => {
  for (final entry in source.entries)
    entry.key: Map<String, dynamic>.from(entry.value),
};

class _UsbApi extends MockApiService {
  final configs = <String, Map<String, Map<String, dynamic>>>{};
  final scripts = <String>[];
  final readConfigs = <String>[];
  final addedConfigs = <String>[];
  final committedConfigs = <String>[];
  bool failWrites = false;
  bool failCommit = false;
  bool failExec = false;
  int _nextSection = 0;

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    readConfigs.add(config);
    return [
      0,
      {'values': _snapshot(configs[config] ?? {})},
    ];
  }

  @override
  Future<dynamic> uciAdd(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String type,
    required Map<String, dynamic> values,
    String? name,
    BuildContext? context,
  }) async {
    if (failWrites) return [6];
    final section = name ?? 'cfg${++_nextSection}';
    (configs[config] ??= {})[section] = {'.type': type, ...values};
    addedConfigs.add(config);
    return [
      0,
      {'section': section},
    ];
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, Object> values,
    BuildContext? context,
  }) async {
    if (failWrites) return [6];
    configs[config]![section]!.addAll(values);
    return [0];
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    if (failCommit) return [6];
    committedConfigs.add(config);
    return [0];
  }

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    final script = params.last;
    scripts.add(script);
    if (failExec) throw Exception('Command failed');
    final stdout = script.startsWith('block info')
        ? '/dev/sdb1: UUID="USB" TYPE="ext4"'
        : script.startsWith('ubus call')
        ? jsonEncode({
            'up': true,
            'ipv4-address': [
              {'address': '10.0.0.2'},
            ],
          })
        : '';
    return [
      0,
      {'code': 0, 'stdout': stdout, 'stderr': ''},
    ];
  }
}

class _UsbAppState extends AppState {
  _UsbAppState()
    : super.forTesting(apiService: _UsbApi(), authService: MockAuthService());

  @override
  String get activeIp => 'router';
  @override
  String get sysauth => 'session';
  @override
  bool get useHttps => false;
}

class _DelayedUsbService extends UsbConfigService {
  _DelayedUsbService() : super(apiService: _UsbApi());
  final profile = Completer<UsbModemProfile>();
  bool profileRequested = false;

  @override
  Future<List<UsbDeviceItem>> getUsbDevices({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async => [];

  @override
  Future<List<UsbDiskPartition>> getStorageDisks({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async => [];

  @override
  Future<UsbModemProfile> getModemProfile({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) {
    profileRequested = true;
    return profile.future;
  }
}
