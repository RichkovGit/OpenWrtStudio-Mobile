import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/forkop_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/router_watchdog_service.dart';
import 'package:luci_mobile/services/sentinel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.openwrt.studio/notifications');
  final notifications = <Map<dynamic, dynamic>>[];
  setUp(() {
    notifications.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'showNotification') {
            notifications.add(call.arguments as Map);
          }
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ForkOP command results', () {
    for (final result in <dynamic>[
      null,
      <dynamic>[],
      <dynamic>[6],
      <dynamic>[
        6,
        {'code': 0, 'stdout': '0'},
      ],
      <dynamic>[
        0,
        {'code': 1, 'stdout': '0'},
      ],
      <dynamic>[
        0,
        {'stdout': '0'},
      ],
    ]) {
      test('selection rejects RPC/command failure $result', () async {
        final api = _RecordingApi()..execResult = result;
        final dio = _offlineController();
        addTearDown(() => dio.close(force: true));
        final service = ForkopService(apiService: api, dioClient: dio);
        expect(
          await service.selectNode(
            routerIp: 'router',
            sysauth: 'session',
            nodeName: 'node',
            groupName: 'explicit-group',
          ),
          isFalse,
        );
      });
    }

    test(
      'CLI success uses exit status, and does not change another group',
      () async {
        final api = _RecordingApi()
          ..execResult = [
            0,
            {'code': 0, 'stdout': ''},
          ];
        final dio = _offlineController();
        addTearDown(() => dio.close(force: true));
        final service = ForkopService(apiService: api, dioClient: dio);
        expect(
          await service.selectNode(
            routerIp: 'router',
            sysauth: 'session',
            nodeName: "one' ; reboot",
            groupName: 'explicit-group',
          ),
          isTrue,
        );
        final command = api.executions.single.params.last;
        expect(command, contains("'one'\\'' ; reboot'"));
        expect(command, isNot(contains('main-out')));
        expect(command, isNot(contains('|| true')));
        expect(command, isNot(contains('uci set')));
      },
    );

    test(
      'successful external controller does not invoke router fallback',
      () async {
        final api = _RecordingApi();
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) => handler.resolve(
                Response(requestOptions: options, statusCode: 204),
              ),
            ),
          );
        addTearDown(() => dio.close(force: true));
        expect(
          await ForkopService(apiService: api, dioClient: dio).selectNode(
            routerIp: 'router',
            sysauth: 'session',
            nodeName: 'node',
          ),
          isTrue,
        );
        expect(api.executions, isEmpty);
      },
    );

    test(
      'service actions reject successful transport with failing exit code',
      () async {
        final api = _RecordingApi()
          ..execResult = [
            0,
            {'code': 127},
          ];
        final dio = _offlineController();
        addTearDown(() => dio.close(force: true));
        final service = ForkopService(apiService: api, dioClient: dio);
        expect(
          await service.restartForkop(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
          ),
          isFalse,
        );
        expect(
          await service.stopForkop(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
          ),
          isFalse,
        );
        expect(
          await service.startForkop(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
          ),
          isFalse,
        );
        expect(
          await service.reloadForkop(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
          ),
          isFalse,
        );
        expect(
          await service.toggleAutostart(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
            enable: true,
          ),
          isFalse,
        );
      },
    );
  });

  group('Sentinel recovery', () {
    testWidgets('reviewer recovery uses the same checked process contract', (
      tester,
    ) async {
      final api = MockApiService();
      final recovery = SentinelService(apiService: api).autoHeal(
        routerIp: 'router',
        sysauth: 'reviewer-session',
        useHttps: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(await recovery, isTrue);
      final dio = _offlineController();
      addTearDown(() => dio.close(force: true));
      final start = ForkopService(apiService: api, dioClient: dio).startForkop(
        routerIp: 'router',
        sysauth: 'reviewer-session',
        useHttps: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(await start, isTrue);
    });
    for (final result in <dynamic>[
      null,
      <dynamic>[6],
      <dynamic>[
        0,
        {'code': 1, 'stdout': 'healed'},
      ],
      <dynamic>[
        6,
        {'code': 0},
      ],
      <dynamic>[
        0,
        {'stdout': 'healed'},
      ],
    ]) {
      test('does not report recovery for failure $result', () async {
        final api = _RecordingApi()..execResult = result;
        expect(
          await SentinelService(
            apiService: api,
          ).autoHeal(routerIp: 'router', sysauth: 'session', useHttps: false),
          isFalse,
        );
      });
    }
    test('recovery succeeds only with checked command completion', () async {
      final api = _RecordingApi()
        ..execResult = [
          0,
          {'code': 0, 'stdout': 'healed'},
        ];
      expect(
        await SentinelService(
          apiService: api,
        ).autoHeal(routerIp: 'router', sysauth: 'session', useHttps: false),
        isTrue,
      );
      expect(
        api.executions.single.params.last.trimLeft(),
        startsWith('set -e'),
      );
    });
  });

  group('Router watchdog sessions', () {
    testWidgets('polls immediately and does not overlap periodic polls', (
      tester,
    ) async {
      final pending = Completer<dynamic>();
      final api = _RecordingApi()..onCall = (_, _, _, _) => pending.future;
      final service = RouterWatchdogService(apiService: api);
      service.startMonitoring(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        interval: const Duration(milliseconds: 100),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(api.calls, hasLength(1));
      service.stopMonitoring();
      pending.complete([6]);
      await tester.pump();
      expect(notifications, isEmpty);
    });

    testWidgets('new router waits for old poll and ignores its stale result', (
      tester,
    ) async {
      final old = Completer<dynamic>();
      final api = _RecordingApi()
        ..onCall = (_, token, _, _) =>
            token == 'old-token' ? old.future : Future.value([6]);
      final service = RouterWatchdogService(apiService: api);
      service.startMonitoring(
        routerIp: 'old-router',
        sysauth: 'old-token',
        useHttps: false,
      );
      service.startMonitoring(
        routerIp: 'new-router',
        sysauth: 'new-token',
        useHttps: true,
      );
      await tester.pump();
      expect(api.calls, hasLength(1));
      old.complete([6]);
      await tester.pump();
      expect(api.calls.map((call) => call.token), ['old-token', 'new-token']);
      expect(notifications, hasLength(1));
      expect(notifications.single['message'], contains('new-router'));
      service.stopMonitoring();
      await tester.pump();
    });

    testWidgets('RPC errors are not interpreted as reachable routers', (
      tester,
    ) async {
      final api = _RecordingApi()..onCall = (_, _, _, _) => Future.value([6]);
      final service = RouterWatchdogService(apiService: api);
      service.startMonitoring(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
      );
      await tester.pump();
      expect(api.calls, hasLength(1));
      expect(api.executions, isEmpty);
      expect(notifications.single['id'], 1001);
      service.stopMonitoring();
    });

    testWidgets(
      'optional unavailable WAN and absent proxy do not cause alerts',
      (tester) async {
        final api = _RecordingApi();
        api.onCall = (_, _, object, _) => Future.value(
          object == 'system'
              ? [
                  0,
                  {'model': 'router'},
                ]
              : [4],
        );
        api.execResult = [
          0,
          {'code': 0, 'stdout': 'ABSENT'},
        ];
        final service = RouterWatchdogService(apiService: api);
        service.startMonitoring(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
        );
        await tester.pump();
        expect(notifications, isEmpty);
        expect(api.executions, hasLength(2));
        service.stopMonitoring();
      },
    );

    testWidgets(
      'identical session is idempotent, replacement resets alert state',
      (tester) async {
        final api = _RecordingApi()..onCall = (_, _, _, _) => Future.value([6]);
        final service = RouterWatchdogService(apiService: api);
        service.startMonitoring(
          routerIp: 'router',
          sysauth: 'first',
          useHttps: false,
        );
        await tester.pump();
        service.startMonitoring(
          routerIp: 'router',
          sysauth: 'first',
          useHttps: false,
        );
        await tester.pump();
        expect(api.calls, hasLength(1));
        expect(notifications, hasLength(1));
        service.startMonitoring(
          routerIp: 'router',
          sysauth: 'second',
          useHttps: false,
        );
        await tester.pump();
        expect(notifications, hasLength(2));
        service.stopMonitoring();
      },
    );

    test('rejects invalid polling intervals and missing sessions', () {
      final service = RouterWatchdogService(apiService: _RecordingApi());
      expect(
        () => service.startMonitoring(
          routerIp: 'router',
          sysauth: 'token',
          useHttps: false,
          interval: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => service.startMonitoring(
          routerIp: 'router',
          sysauth: '',
          useHttps: false,
        ),
        throwsArgumentError,
      );
      expect(service.isMonitoring, isFalse);
    });
  });
}

Dio _offlineController() => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      ),
    ),
  );

class _RecordingApi implements IApiService {
  dynamic execResult = [
    0,
    {'code': 0, 'stdout': ''},
  ];
  Future<dynamic> Function(String, String, String, String)? onCall;
  final calls = <({String ip, String token, String object})>[];
  final executions = <({String ip, String token, List<String> params})>[];

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    calls.add((ip: ipAddress, token: sysauth, object: object));
    return onCall == null
        ? [
            0,
            {'model': 'router'},
          ]
        : await onCall!(ipAddress, sysauth, object, method);
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
    executions.add((ip: ipAddress, token: sysauth, params: params));
    return execResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
