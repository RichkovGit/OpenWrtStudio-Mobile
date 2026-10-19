import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('Wi-Fi cards fit at scale $scale', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStateProvider.overrideWith((ref) => _WirelessState()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cudy_OpenWrt_2.4Ghz_LongNetworkName'), findsOneWidget);
      expect(find.text('Richkov5Guest'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

class _WirelessState extends AppState {
  _WirelessState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  @override
  bool get dashboardFetchIsFresh => true;
  @override
  Map<String, dynamic>? get dashboardData => {
    'wireless': {
      'radio0': {
        'interfaces': [
          for (final ssid in [
            'Cudy_OpenWrt_2.4Ghz_LongNetworkName',
            'Richkov5Guest',
          ])
            {
              'config': {'ssid': ssid},
              'iwinfo': {'signal': -49, 'channel': 1},
            },
        ],
      },
    },
  };
}
