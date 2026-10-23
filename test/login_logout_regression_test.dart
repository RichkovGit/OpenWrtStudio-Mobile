import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Studio',
      packageName: 'studio.test',
      version: '2.5.25',
      buildNumber: '4525',
      buildSignature: 'test',
    );
  });
  for (final reviewer in [false, true]) {
    testWidgets('explicit logout does not reconnect (reviewer=$reviewer)', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        AppConfig.reviewerModeKey: '$reviewer',
      });
      final state = _LoginState();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: MaterialApp(
            initialRoute: '/login',
            routes: {
              '/login': (_) => const LoginScreen(attemptAutoLogin: false),
              '/': (_) => const Text('Automatically reconnected'),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(state.autoLoginAttempts, 0);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Automatically reconnected'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('startup still attempts saved-router login', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      AppConfig.reviewerModeKey: 'false',
    });
    final state = _LoginState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.autoLoginAttempts, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LoginState extends AppState {
  _LoginState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );
  int autoLoginAttempts = 0;
  @override
  Future<bool> tryAutoLogin({BuildContext? context}) async {
    autoLoginAttempts++;
    return false;
  }
}
