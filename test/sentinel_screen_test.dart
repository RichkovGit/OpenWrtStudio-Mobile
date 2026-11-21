import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/sentinel_target.dart';
import 'package:luci_mobile/screens/sentinel_screen.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/router_session.dart';

RouterSession _session(String token) => RouterSession(
  routerId: 'r1',
  ipAddress: '10.0.0.1',
  sysauth: token,
  useHttps: false,
  token: token == 'tokA' ? 1 : 2,
);

class _SentinelState extends AppState {
  _SentinelState(IApiService api, {RouterSession? session})
    : _session = session,
      super.forTesting(apiService: api, authService: MockAuthService());

  RouterSession? _session;

  @override
  RouterSession? get currentSession => _session;

  void switchTo(RouterSession? session) {
    _session = session;
    notifyListeners();
  }
}

Future<void> _pump(WidgetTester tester, _SentinelState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: const MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: SentinelScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _probeOutput(SentinelStatus status) => SentinelTarget.defaultTargets()
    .map(
      (t) =>
          '${t.name}:${status == SentinelStatus.online ? 'online:42' : 'blocked:0'}',
    )
    .join('\n');

void main() {
  testWidgets('renders localized strings and a completed check', (
    tester,
  ) async {
    final state = _SentinelState(MockApiService(), session: _session('tokA'));
    await _pump(tester, state);
    expect(find.text('Sentinel Watchdog'), findsOneWidget);
    expect(find.text('Fix everything'), findsOneWidget);
    expect(find.text('Tunneling is active'), findsOneWidget);
    expect(find.text('6 of 6 checkpoint services reachable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fix-all shows progress then a per-step report', (tester) async {
    final state = _SentinelState(MockApiService(), session: _session('tokA'));
    await _pump(tester, state);

    await tester.tap(find.text('Fix everything'));
    await tester.pump();
    expect(find.text('Step 1 of 3: Restart DNS (dnsmasq)'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Repair report'), findsOneWidget);
    expect(find.text('Fixed: 3. Failed: 0. Skipped: 0.'), findsOneWidget);
    expect(find.text('Fixed (mihomo)'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Repair report'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a denied check surfaces the error with a retry', (tester) async {
    final state = _SentinelState(_DeniedApi(), session: _session('tokA'));
    await _pump(tester, state);
    expect(find.text('Could not check connectivity'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Fix everything'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no session disables actions without crashing', (tester) async {
    final state = _SentinelState(MockApiService());
    await _pump(tester, state);
    final fixButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(fixButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stale probe from the previous router is discarded', (
    tester,
  ) async {
    final pending = Completer<dynamic>();
    final api = _SwitchApi(pending);
    final state = _SentinelState(api, session: _session('tokA'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(
          localizationsDelegates: luciLocalizationsDelegates,
          home: SentinelScreen(),
        ),
      ),
    );
    await tester.pump(); // probe for router A is in flight

    state.switchTo(_session('tokB'));
    await tester.pump();

    // Router A answers late, after the switch: its "all online" must not
    // be shown as router B's connectivity.
    pending.complete([
      0,
      {'code': 0, 'stdout': _probeOutput(SentinelStatus.online)},
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Tunneling is active'), findsNothing);
    expect(find.text('Connectivity problems detected'), findsOneWidget);
    expect(find.text('0 of 6 checkpoint services reachable'), findsOneWidget);
    expect(api.tokens, contains('tokB'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _DeniedApi extends MockApiService {
  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async => [6];
}

class _SwitchApi extends MockApiService {
  _SwitchApi(this.pending);
  final Completer<dynamic> pending;
  final tokens = <String>[];

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    tokens.add(sysauth);
    if (sysauth == 'tokA') return pending.future;
    return [
      0,
      {'code': 0, 'stdout': _probeOutput(SentinelStatus.blocked)},
    ];
  }
}
