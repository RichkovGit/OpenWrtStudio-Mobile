import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/protocols_screen.dart';
import 'package:luci_mobile/screens/simple_dashboard_screen.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/models/protocol_item.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/protocol_service.dart';

String scanOutput({
  String packages = '',
  String bins = '',
  String services = '',
  String processes = '',
}) =>
    '''
===PKGS===
$packages
===BINS===
$bins
===SERVICES===
$services
===MODULES===
===PROCS===
$processes
===DONE===
''';

class ScanApi extends MockApiService {
  ScanApi(String output)
    : response = [
        0,
        {'code': 0, 'stdout': output},
      ];
  dynamic response;
  dynamic controlResponse = [
    0,
    {'code': 0},
  ];
  final commands = <String>[];

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async => [
    0,
    {'values': <String, dynamic>{}},
  ];

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    if (command == '/bin/sh' && params.contains(ProtocolService.scanScript)) {
      return response;
    }
    commands.add('$command ${params.join(' ')}');
    return controlResponse;
  }
}

Future<List<ProtocolItem>> scan(ScanApi api) => ProtocolService(
  apiService: api,
).scanProtocols(routerIp: 'router', sysauth: 'session', useHttps: false);

class _ProtocolState extends AppState {
  _ProtocolState(ScanApi api)
    : super.forTesting(apiService: api, authService: MockAuthService());

  @override
  model.Router? get selectedRouter => model.Router(
    id: 'r1',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
  );

  @override
  String? get sysauth => 'session';

  @override
  String? get activeIp => 'router';

  @override
  Future<void> fetchDashboardData({bool isRetryAfterFallback = false}) async {}
}

class _ScanFactory extends ReviewerModeServiceFactory {
  _ScanFactory(this.api);
  final ScanApi api;
  @override
  ScanApi createApiService() => api;
}

Future<void> _pumpProtocols(WidgetTester tester, ScanApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => _ProtocolState(api))],
      child: const MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: ProtocolsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('simple mode clears stopped console processes on refresh', (
    tester,
  ) async {
    final api = ScanApi(scanOutput(processes: 'xray'));
    ServiceContainer.instance.setFactory(_ScanFactory(api));
    addTearDown(() => ServiceContainer.configure(reviewerMode: true));
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStateProvider.overrideWith((ref) => _ProtocolState(api)),
        ],
        child: MaterialApp(
          localizationsDelegates: luciLocalizationsDelegates,
          home: SimpleDashboardScreen(onSwitchToExpert: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('🟢 Активен: Xray-core'), findsOneWidget);
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNull);
    api.response = [
      0,
      {'code': 0, 'stdout': scanOutput()},
    ];
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('🟢 Активен: Xray-core'), findsNothing);
    expect(find.text('РАБОТАЕТ'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      api.commands.where((c) => !c.contains('uci -q show wireless')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('console Xray is visible without unusable service buttons', (
    tester,
  ) async {
    final api = ScanApi(scanOutput(processes: 'xray'));
    await _pumpProtocols(tester, api);
    await tester.scrollUntilVisible(find.text('Xray-core'), 400);
    final card = find.ancestor(
      of: find.text('Xray-core'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: card, matching: find.text('Работает')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(
          'Запущен вручную на роутере. Управление — через консоль.',
        ),
      ),
      findsOneWidget,
    );
    for (final label in [
      'Установить',
      'Старт',
      'Стоп',
      'Перезапуск',
      'Переключить',
    ]) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsNothing,
      );
    }
    expect(api.commands, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('denied scan explains the error instead of offering installs', (
    tester,
  ) async {
    final api = ScanApi('')..response = [6];
    await _pumpProtocols(tester, api);
    expect(find.text('Не удалось проверить протоколы'), findsOneWidget);
    expect(find.text('Установить'), findsNothing);
    expect(find.text('Повторить'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'standalone Xray needs no package, PATH binary, UCI or init script',
    () async {
      final items = await scan(ScanApi(scanOutput(processes: 'xray')));
      final xray = items.singleWhere((p) => p.id == 'xray');
      expect(xray.isInstalled, isTrue);
      expect(xray.isRunning, isTrue);
      expect(xray.isManuallyStarted, isTrue);
      expect(xray.canControlService, isFalse);
      expect(items.where((p) => p.isRunning).map((p) => p.id), ['xray']);
      final restored = ProtocolItem.fromJson(xray.toJson());
      expect(restored.copyWith().isManuallyStarted, isTrue);
      expect(restored.canControlService, isFalse);
    },
  );

  test('managed and manually started instances are distinguished', () async {
    for (final service in ['running', 'stopped']) {
      final xray = (await scan(
        ScanApi(scanOutput(services: 'xray:$service', processes: 'xray')),
      )).singleWhere((p) => p.id == 'xray');
      expect(xray.hasService, isTrue);
      expect(xray.isRunning, isTrue);
      expect(xray.isManuallyStarted, service == 'stopped');
      expect(xray.canControlService, service == 'running');
    }
  });

  test(
    'known daemon aliases are exact and do not imply other wrappers',
    () async {
      final items = await scan(
        ScanApi(
          scanOutput(
            processes: 'xray-core\nclash\ntailscaled\nzerotier-one\nsing-box',
          ),
        ),
      );
      expect(items.where((p) => p.isRunning).map((p) => p.id).toSet(), {
        'xray',
        'mihomo',
        'tailscale',
        'zerotier',
        'sing-box',
      });
      expect(items.singleWhere((p) => p.id == 'forkop').isInstalled, isFalse);
    },
  );

  test('helper names and argument paths are not running cores', () async {
    final items = await scan(
      ScanApi(
        scanOutput(
          packages: 'xray-geodata',
          bins: '/tmp/not-xray-helper',
          processes:
              'xray-helper\n/etc/xray/config.json\ntailscale\nzerotier-cli',
        ),
      ),
    );
    expect(items.any((p) => p.isRunning), isFalse);
    expect(items.singleWhere((p) => p.id == 'xray').isInstalled, isFalse);
  });

  test(
    'an installed binary alone is not a running or controllable service',
    () async {
      final xray = (await scan(
        ScanApi(scanOutput(bins: '/opt/bin/xray')),
      )).singleWhere((p) => p.id == 'xray');
      expect(xray.isInstalled, isTrue);
      expect(xray.isRunning, isFalse);
      expect(xray.canControlService, isFalse);
    },
  );

  test(
    'denied or incomplete scans cannot report everything uninstalled',
    () async {
      for (final response in <dynamic>[
        [6],
        [0],
        [
          0,
          {'code': 1, 'stdout': scanOutput()},
        ],
        [
          0,
          {'code': 0, 'stdout': '===PKGS===\nxray-core'},
        ],
      ]) {
        final api = ScanApi('')..response = response;
        await expectLater(
          scan(api),
          throwsA(anyOf(isA<RpcException>(), isA<StateError>())),
        );
      }
    },
  );

  test(
    'switching to a console process does not stop another VPN first',
    () async {
      final api = ScanApi(
        scanOutput(services: 'openvpn:running', processes: 'xray'),
      );
      final success = await ProtocolService(apiService: api).switchProtocol(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        targetServiceName: 'xray',
        currentServiceName: 'openvpn',
      );
      expect(success, isFalse);
      expect(api.commands, isEmpty);
    },
  );

  test('switching cannot interfere with a manually started core', () async {
    final api = ScanApi(
      scanOutput(services: 'openvpn:stopped', processes: 'xray'),
    );
    final success = await ProtocolService(apiService: api).switchProtocol(
      routerIp: 'router',
      sysauth: 'session',
      useHttps: false,
      targetServiceName: 'openvpn',
      currentServiceName: 'xray',
    );
    expect(success, isFalse);
    expect(api.commands, isEmpty);
  });

  test('a failed stop prevents starting another service', () async {
    final api = ScanApi(scanOutput(services: 'openvpn:running\nxray:stopped'))
      ..controlResponse = [
        0,
        {'code': 1},
      ];
    final success = await ProtocolService(apiService: api).switchProtocol(
      routerIp: 'router',
      sysauth: 'session',
      useHttps: false,
      targetServiceName: 'xray',
      currentServiceName: 'openvpn',
    );
    expect(success, isFalse);
    expect(api.commands, ['/etc/init.d/openvpn stop']);
  });

  test(
    'an unrelated console mesh process does not block a managed target',
    () async {
      final api = ScanApi(
        scanOutput(services: 'openvpn:stopped', processes: 'tailscaled'),
      );
      expect(
        await ProtocolService(apiService: api).switchProtocol(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          targetServiceName: 'openvpn',
        ),
        isTrue,
      );
      expect(api.commands, ['/etc/init.d/openvpn start']);
    },
  );

  test(
    'service control requires successful RPC and process exit code',
    () async {
      for (final response in <dynamic>[
        null,
        [6],
        [0],
        [
          0,
          {'code': 1},
        ],
      ]) {
        final api = ScanApi('')..controlResponse = response;
        expect(
          await ProtocolService(apiService: api).controlService(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
            serviceName: 'xray',
            action: 'restart',
          ),
          isFalse,
        );
      }
      final api = ScanApi('');
      expect(
        await ProtocolService(apiService: api).controlService(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          serviceName: 'xray',
          action: 'restart',
        ),
        isTrue,
      );
    },
  );
}
