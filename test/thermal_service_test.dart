import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/thermal_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/thermal_service.dart';
import 'package:luci_mobile/state/app_state.dart';

void main() {
  test('thermal and hwmon readings retain driver labels and millidegrees', () {
    final values = ThermalService.parse('''
/sys/class/thermal/thermal_zone2/temp|cpu-thermal|54321
/sys/class/hwmon/hwmon0/temp1_input|wifi|500
/sys/class/hwmon/hwmon0/temp2_input|radio2|bad
/sys/class/hwmon/hwmon1/temp1_input|ambient|-500
''');
    expect(values.map((s) => s.celsius), [54.321, 0.5, null, -0.5]);
    expect(values.first.label, 'cpu-thermal');
    expect(ThermalService.parse(''), isEmpty);
  });

  testWidgets('unsupported firmware shows no invented sensors or chip model', (
    tester,
  ) async {
    final state = _State(_Api(['']));
    await _show(tester, state);
    expect(find.textContaining('Прошивка не предоставляет'), findsOneWidget);
    expect(find.textContaining('61.3'), findsNothing);
    expect(find.textContaining('MediaTek'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('sensor polling refreshes values and clears them after read failure', (
    tester,
  ) async {
    final state = _State(_Api([
      '/sys/class/thermal/thermal_zone0/temp|soc|42000',
      '/sys/class/thermal/thermal_zone0/temp|soc|43000',
      null,
    ]));
    await _show(tester, state);
    expect(find.text('42.0 °C'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('43.0 °C'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('43.0 °C'), findsNothing);
    expect(find.textContaining('Не удалось прочитать температуру'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}

Future<void> _show(WidgetTester tester, _State state) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [appStateProvider.overrideWith((ref) => state)],
    child: const MaterialApp(home: ThermalScreen()),
  ));
  await tester.pumpAndSettle();
}

class _State extends AppState {
  _State(_Api api) : super.forTesting(apiService: api, authService: MockAuthService());
}

class _Api extends MockApiService {
  final List<String?> outputs;
  _Api(this.outputs);
  @override
  Future<dynamic> systemExec(String ipAddress, String sysauth, bool useHttps, {
    required String command, List<String> params = const [], BuildContext? context,
  }) async {
    final output = outputs.length > 1 ? outputs.removeAt(0) : outputs.single;
    return [0, {'code': output == null ? 1 : 0, 'stdout': output ?? ''}];
  }
}
