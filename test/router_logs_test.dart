import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/screens/log_screen.dart';
import 'package:luci_mobile/screens/commands_screen.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/screens/system_logs_screen.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/diagnostics_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/router_logs_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/router_session.dart';

const session = RouterSession(
  routerId: 'one',
  ipAddress: 'router',
  sysauth: 'session',
  useHttps: false,
  token: 1,
);

class _LogsApi extends MockApiService {
  dynamic native = [6];
  Object? nativeError;
  Object? directError;
  String system = 'system-entry';
  String kernel = '[0.01] kernel-entry';
  final nativeCalls = <Map<String, dynamic>?>[];
  final directCalls = <bool>[];
  Completer<String>? pending;
  @override
  Future<dynamic> call(
    String ip,
    String token,
    bool https, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    if (object != 'log' || method != 'read') {
      throw StateError('Unexpected RPC in log reader');
    }
    nativeCalls.add(params);
    if (nativeError != null) throw nativeError!;
    return native;
  }

  @override
  Future<String> readLogDirect(
    String ip,
    String token,
    bool https, {
    required bool kernel,
    BuildContext? context,
  }) async {
    directCalls.add(kernel);
    if (directError != null) throw directError!;
    if (pending != null && ip == 'router') return pending!.future;
    return kernel ? this.kernel : system;
  }
}

Future<void> _pumpLogs(
  WidgetTester tester,
  _LogsApi api, {
  Widget page = const LogScreen(),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(session),
        apiServiceProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'native log.read is one-shot and preserves time, severity and message',
    () async {
      final api = _LogsApi()
        ..native = [
          0,
          {
            'log': [
              {'time': 0, 'priority': 27, 'msg': 'critical diagnostic'},
            ],
          },
        ];
      final output = await RouterLogsService(api).read(session, kernel: false);
      expect(api.nativeCalls.single, {
        'lines': 200,
        'stream': false,
        'oneshot': true,
      });
      expect(api.directCalls, isEmpty);
      final entry = LogEntry.parseAll(output).single;
      expect(entry.timestamp, '1970-01-01T00:00:00.000Z');
      expect(entry.facility, 'daemon');
      expect(entry.isProblem, isTrue);
      expect(entry.message, 'critical diagnostic');
    },
  );

  test(
    'successful empty syslog is never replaced with kernel or CGI output',
    () async {
      final api = _LogsApi()
        ..native = [
          0,
          {'log': []},
        ];
      expect(await RouterLogsService(api).read(session, kernel: false), '');
      expect(api.directCalls, isEmpty);
    },
  );

  test(
    'older or restricted log.read uses only the system log CGI reader',
    () async {
      for (final response in <dynamic>[
        [6],
        [4],
        [0, {}],
        [
          0,
          {
            'log': [null],
          },
        ],
      ]) {
        final api = _LogsApi()..native = response;
        expect(
          await DiagnosticsService(api).systemLog(session),
          'system-entry',
        );
        expect(api.directCalls, [false]);
      }
    },
  );

  test('kernel log does not use log.read or a general shell', () async {
    final api = _LogsApi();
    expect(
      await DiagnosticsService(api).kernelLog(session),
      '[0.01] kernel-entry',
    );
    expect(api.nativeCalls, isEmpty);
    expect(api.directCalls, [true]);
  });

  test(
    'denied CGI remains an error rather than an empty log or another source',
    () async {
      final api = _LogsApi()
        ..directError = const RpcException(
          object: 'cgi-io',
          method: 'systemLog',
          status: 6,
        );
      await expectLater(
        RouterLogsService(api).read(session, kernel: false),
        throwsA(isA<RpcException>()),
      );
      expect(api.directCalls, [false]);
    },
  );

  test('network failure is not retried through another transport', () async {
    final api = _LogsApi()..nativeError = TimeoutException('router offline');
    await expectLater(
      RouterLogsService(api).read(session, kernel: false),
      throwsA(isA<TimeoutException>()),
    );
    expect(api.directCalls, isEmpty);
  });

  test(
    'line limits are bounded and the most recent lines are retained',
    () async {
      final api = _LogsApi()
        ..native = [
          0,
          {
            'log': [
              for (var i = 0; i < 1002; i++)
                {'time': i, 'priority': 30, 'msg': 'event-$i'},
            ],
          },
        ];
      final output = await RouterLogsService(
        api,
      ).read(session, kernel: false, lines: 50000);
      expect(api.nativeCalls.single?['lines'], 1000);
      expect(output.split('\n'), hasLength(1000));
      expect(output, endsWith('event-1001'));
      api.system = 'one\r\ntwo\r\nthree\r\n';
      api.native = [6];
      expect(
        await RouterLogsService(api).read(session, kernel: false, lines: 2),
        'two\nthree',
      );
    },
  );

  testWidgets('both log sources use the same reader and filter locally', (
    tester,
  ) async {
    final api = _LogsApi();
    await _pumpLogs(tester, api);
    expect(find.text('system-entry'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'no-match');
    await tester.pump();
    expect(find.text('No lines match that filter'), findsOneWidget);
    expect(api.directCalls, [false]);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Kernel log'));
    await tester.pumpAndSettle();
    expect(find.text('[0.01] kernel-entry'), findsOneWidget);
    expect(find.text('system-entry'), findsNothing);
    expect(api.directCalls, [false, true]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'legacy Studio entry shows read errors without saying the journal is empty',
    (tester) async {
      final api = _LogsApi()
        ..directError = const RpcException(
          object: 'cgi-io',
          method: 'systemLog',
          status: 6,
        );
      await _pumpLogs(tester, api, page: const SystemLogsScreen());
      expect(find.text('Could not read the log'), findsOneWidget);
      expect(find.text('The log is empty'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'the kernel log shortcut opens the reader instead of a shell command',
    (tester) async {
      final api = _LogsApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(session),
            apiServiceProvider.overrideWithValue(api),
            appStateProvider.overrideWith(
              (ref) => AppState.forTesting(
                apiService: api,
                authService: MockAuthService(),
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: luciLocalizationsDelegates,
            home: CommandsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Kernel Messages (dmesg)'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Kernel Messages (dmesg)'));
      await tester.pumpAndSettle();
      expect(find.byType(LogScreen), findsOneWidget);
      expect(find.text('[0.01] kernel-entry'), findsOneWidget);
      expect(api.nativeCalls, isEmpty);
      expect(api.directCalls, [true]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an older router response cannot replace logs from a new session',
    (tester) async {
      final api = _LogsApi()
        ..pending = Completer<String>()
        ..system = 'new-router-entry';
      final selected = StateProvider<RouterSession?>((ref) => session);
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => ref.watch(selected)),
          apiServiceProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: luciLocalizationsDelegates,
            home: LogScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      container.read(selected.notifier).state = const RouterSession(
        routerId: 'two',
        ipAddress: 'other-router',
        sysauth: 'new-session',
        useHttps: false,
        token: 2,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('new-router-entry'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('|'),
      );
      api.pending!.complete('old-router-entry');
      await tester.pumpAndSettle();
      expect(find.text('old-router-entry'), findsNothing);
      expect(
        find.text('new-router-entry'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('|'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
