import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/simple_dashboard_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/state/app_state.dart';

void main() {
  for (final width in [360.0, 800.0]) {
    testWidgets(
      'dashboard mode selector fits a $width px header with back navigation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        ServiceContainer.configure(reviewerMode: true);
        var switches = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith((ref) => _DashboardState()),
            ],
            child: MaterialApp(
              initialRoute: '/simple',
              routes: {
                '/': (context) => const SizedBox.shrink(),
                '/simple': (context) =>
                    SimpleDashboardScreen(onSwitchToExpert: () => switches++),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final title = tester.getRect(find.text('OpenWrt Studio'));
        final selector = tester.getRect(find.byType(SegmentedButton<bool>));
        expect(selector.left, greaterThanOrEqualTo(0));
        expect(selector.right, lessThanOrEqualTo(width));
        if (width < 560) {
          expect(selector.top, greaterThanOrEqualTo(title.bottom));
        } else {
          expect(selector.left, greaterThanOrEqualTo(title.right));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Эксперт'));
        await tester.pump();
        expect(switches, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

class _DashboardState extends AppState {
  _DashboardState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  @override
  String? get activeIp => null;
  @override
  String? get sysauth => null;
  @override
  bool get isConnected => false;
}
