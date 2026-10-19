import 'package:luci_mobile/navigation/luci_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/manage_routers_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('Russian add-router dialog fits a narrow phone at $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final state = _SwitchingAppState();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: MaterialApp(
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru')],
            localizationsDelegates: luciLocalizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ManageRoutersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить роутер'));
      await tester.pumpAndSettle();
      expect(find.text('Добавить резервный адрес'), findsOneWidget);
      expect(find.text('🔍 Автопоиск'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'switching a router requests the dashboard before disposing its route',
    (tester) async {
      final state = _SwitchingAppState();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ManageRoutersScreen(),
                    ),
                  ),
                  child: const Text('Open routers'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open routers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('192.168.1.2'));
      await tester.pumpAndSettle();
      expect(find.byType(ManageRoutersScreen), findsNothing);
      expect(state.requestedTab, LuciTab.dashboard);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fallback removal requires confirmation', (tester) async {
    final state = _TestAppState(
      model.Router(
        id: 'router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        alternateAddress: 'router.example.com',
        alternateUseHttps: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: ManageRoutersScreen()),
      ),
    );

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter, isNull);

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter?.hasFallback, isFalse);
  });
}

class _SwitchingAppState extends AppState {
  _SwitchingAppState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );
  final first = model.Router(
    id: 'first',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
  );
  final second = model.Router(
    id: 'second',
    ipAddress: '192.168.1.2',
    username: 'root',
    password: '',
    useHttps: false,
  );
  model.Router? _selected;
  @override
  List<model.Router> get routers => [first, second];
  @override
  model.Router? get selectedRouter => _selected ?? first;
  @override
  Future<void> selectRouter(String id, {BuildContext? context}) async {
    _selected = second;
    notifyListeners();
  }
}

class _TestAppState extends AppState {
  _TestAppState(this.router)
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final model.Router router;
  model.Router? updatedRouter;

  @override
  List<model.Router> get routers => [router];

  @override
  Future<void> updateRouter(model.Router router) async =>
      updatedRouter = router;
}
