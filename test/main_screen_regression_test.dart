import 'package:luci_mobile/navigation/luci_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/main_screen.dart';
import 'package:luci_mobile/screens/simple_dashboard_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_watchdog_service.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/state/app_state.dart';

void main() {
  setUp(() => ServiceContainer.instance.setFactory(_ScreenServiceFactory()));
  tearDown(() => RouterWatchdogService.instance.stopMonitoring());

  testWidgets('expert dashboard can return to simple mode without logout', (
    tester,
  ) async {
    final state = _ScreenState();
    await _show(tester, state);
    await tester.tap(find.byTooltip('Simple mode'));
    await tester.pump();
    expect(state.isExpertMode, isFalse);
    expect(find.byType(SimpleDashboardScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('upstream settings keeps Studio tools reachable', (tester) async {
    await _show(tester, _ScreenState(), initialTab: LuciTab.settings);
    await tester.tap(find.text('OpenWrt Studio'));
    await tester.pumpAndSettle();
    expect(find.text('ForkOP Прокси и Серверы'), findsOneWidget);
    expect(find.text('VPN и Протоколы'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('request for current tab is consumed before next navigation', (
    tester,
  ) async {
    final state = _ScreenState();
    await _show(tester, state);
    state.requestTab(LuciTab.dashboard);
    await tester.pump();
    expect(state.requestedTab, isNull);
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(state.requestedTab, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('invalid initial tab safely opens dashboard', (tester) async {
    await _show(tester, _ScreenState(), initialTab: LuciTab.fromIndex(99));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('watchdog follows foreground, logout, and screen disposal', (
    tester,
  ) async {
    final state = _ScreenState()..token = 'session';
    await _show(tester, state);
    expect(RouterWatchdogService.instance.isMonitoring, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(RouterWatchdogService.instance.isMonitoring, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(RouterWatchdogService.instance.isMonitoring, isTrue);
    state.changeSession(null);
    await tester.pump();
    expect(RouterWatchdogService.instance.isMonitoring, isFalse);
    state.changeSession('new-session');
    await tester.pump();
    expect(RouterWatchdogService.instance.isMonitoring, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(RouterWatchdogService.instance.isMonitoring, isFalse);
  });

  testWidgets('watchdog stops during a saved-router switch with stale auth', (
    tester,
  ) async {
    final state = _ScreenState()..token = 'old-session';
    await _show(tester, state);
    expect(RouterWatchdogService.instance.isMonitoring, isTrue);
    state.selectAddress('new-router');
    await tester.pump();
    expect(RouterWatchdogService.instance.isMonitoring, isFalse);
    state.authIp = 'new-router';
    state.changeSession('new-session');
    await tester.pump();
    expect(RouterWatchdogService.instance.isMonitoring, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final useHttps in [false, true]) {
    testWidgets(
      'equivalent ${useHttps ? 'HTTPS' : 'HTTP'} endpoints keep monitoring',
      (tester) async {
        final state = _ScreenState()
          ..token = 'session'
          ..https = useHttps;
        state.selectAddress(
          '${useHttps ? 'https' : 'http'}://ROUTER:${useHttps ? 443 : 80}/',
        );
        await _show(tester, state);
        expect(RouterWatchdogService.instance.isMonitoring, isTrue);
        state.selectAddress('router:8080');
        await tester.pump();
        expect(RouterWatchdogService.instance.isMonitoring, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  testWidgets('equivalent IPv6 forms match the same authenticated router', (
    tester,
  ) async {
    final state = _ScreenState()
      ..token = 'session'
      ..authIp = '2001:db8::1'
      ..https = true;
    state.selectAddress('HTTPS://[2001:0db8:0:0:0:0:0:1]:443/');
    await _show(tester, state);
    expect(RouterWatchdogService.instance.isMonitoring, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

Future<void> _show(
  WidgetTester tester,
  _ScreenState state, {
  LuciTab? initialTab,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: MaterialApp(home: MainScreen(initialTab: initialTab)),
    ),
  );
  await tester.pump();
}

class _ScreenState extends AppState {
  _ScreenState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );
  String? token;
  String authIp = 'router';
  bool https = false;
  bool expert = true;
  model.Router? selected;
  @override
  model.Router? get selectedRouter => selected;
  @override
  bool get useHttps => https;
  @override
  bool get isExpertMode => expert;
  @override
  void setExpertMode(bool value) {
    expert = value;
    notifyListeners();
  }

  @override
  bool get isAuthenticated => token != null;
  @override
  String? get sysauth => token;
  @override
  String? get activeIp => token == null ? null : authIp;
  @override
  Future<void> fetchDashboardData({bool isRetryAfterFallback = false}) async {}
  void changeSession(String? value) {
    token = value;
    notifyListeners();
  }

  void selectAddress(String value) {
    selected = model.Router(
      id: 'selected',
      ipAddress: value,
      username: 'root',
      password: '',
      useHttps: https,
    );
    notifyListeners();
  }
}

class _ScreenServiceFactory extends ReviewerModeServiceFactory {
  @override
  IApiService createApiService() => _ImmediateWatchdogApi();
}

class _ImmediateWatchdogApi extends MockApiService {
  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async => [
    0,
    object == 'system' ? {'model': 'Test router'} : {'up': true},
  ];

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async => [
    0,
    {'code': 0, 'stdout': 'ABSENT', 'stderr': ''},
  ];
}
