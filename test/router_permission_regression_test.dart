import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/commands_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/thermal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<ThermalReading>> read(_Files api) =>
      ThermalService(api).read(ip: 'router', token: 'session', useHttps: false);

  test(
    'shell denied but permitted file reads recover actual temperatures',
    () async {
      final api = _Files();
      final readings = await read(api);
      expect(readings.map((s) => s.celsius), [42.5, 51.0]);
      expect(readings.map((s) => s.label), ['soc', 'radio']);
      expect(api.calls.every((c) => ['list', 'read'].contains(c.$1)), isTrue);
      expect(api.calls.any((c) => c.$2.contains('..')), isFalse);
    },
  );

  test(
    'file permissions are respected and not reported as absent sensors',
    () async {
      final api = _Files()..denyReads = true;
      await expectLater(
        read(api),
        throwsA(
          isA<RpcException>().having(
            (e) => e.isAccessDenied,
            'permission denial',
            true,
          ),
        ),
      );
    },
  );

  test(
    'a permitted sensor survives denied labels and the other sensor',
    () async {
      final api = _Files()..partial = true;
      final readings = await read(api);
      expect(readings, hasLength(1));
      expect(readings.single.celsius, 42.5);
      expect(readings.single.label, 'thermal_zone0');
    },
  );

  test('empty successful enumeration reports no sensors', () async {
    final api = _Files()..empty = true;
    expect(await read(api), isEmpty);
  });

  test('connection failure does not trigger another transport path', () async {
    final api = _Files()..transportError = true;
    await expectLater(read(api), throwsStateError);
    expect(api.calls, isEmpty);
  });

  test(
    'terminal rejects denied or malformed results rather than returning zero',
    () async {
      for (final result in <dynamic>[
        [6],
        [0],
        [0, {}],
        [
          0,
          {'code': '0'},
        ],
      ]) {
        final value = await CommandsService(apiService: _Exec(result)).execute(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
          command: 'uptime',
        );
        expect(value.isSuccess, isFalse);
        expect(value.error, isNotNull);
      }
      final value =
          await CommandsService(
            apiService: _Exec([
              0,
              {'code': 0, 'stdout': 'ok'},
            ]),
          ).execute(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
            command: 'uptime',
          );
      expect(value.isSuccess, isTrue);
      expect(value.stdout, 'ok');
      expect(value.error, isNull);
    },
  );

  for (final language in ['ru', 'en']) {
    testWidgets('file.exec denial explains router permissions in $language', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: luciLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(
              apiErrorText(
                context,
                const RpcException(object: 'file', method: 'exec', status: 6),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('/bin/sh'), findsOneWidget);
      expect(
        find.textContaining(
          language == 'ru'
              ? 'Root на Android не нужен'
              : 'Android root is not required',
        ),
        findsOneWidget,
      );
    });
  }
}

class _Exec extends MockApiService {
  final dynamic response;
  _Exec(this.response);
  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async => response;
}

class _Files extends MockApiService {
  final calls = <(String, String)>[];
  bool denyReads = false,
      partial = false,
      empty = false,
      transportError = false;
  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    if (transportError) throw StateError('connection failed');
    throw const RpcException(object: 'file', method: 'exec', status: 6);
  }

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
    expect(object, 'file');
    final path = params!['path'] as String;
    calls.add((method, path));
    if (denyReads || (partial && method == 'read' && !path.endsWith('/temp'))) {
      return [6];
    }
    if (method == 'list') {
      final names = empty
          ? <String>[]
          : switch (path) {
              '/sys/class/thermal' => [
                'thermal_zone0',
                '../etc',
                'thermal_zoneevil',
              ],
              '/sys/class/hwmon' => ['hwmon0'],
              '/sys/class/hwmon/hwmon0' => ['temp1_input', '../shadow'],
              _ => <String>[],
            };
      return [
        0,
        {
          'entries': names.map((name) => {'name': name}).toList(),
        },
      ];
    }
    final value = switch (path) {
      '/sys/class/thermal/thermal_zone0/temp' => '42500\n',
      '/sys/class/thermal/thermal_zone0/type' => 'soc',
      '/sys/class/hwmon/hwmon0/temp1_input' => '51000\n',
      '/sys/class/hwmon/hwmon0/temp1_label' => 'radio',
      _ => null,
    };
    return value == null
        ? [4]
        : [
            0,
            {'data': value},
          ];
  }
}
