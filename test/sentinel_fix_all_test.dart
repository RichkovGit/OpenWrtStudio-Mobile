import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/sentinel_fix_report.dart';
import 'package:luci_mobile/models/sentinel_target.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/sentinel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fix-all orchestration', () {
    test('runs every step in order with progress and a full report', () async {
      final api = _FixApi({
        'dns': 'OWS_FIX=fixed',
        'bypass': 'OWS_FIX=fixed:mihomo',
        'firewall': 'OWS_FIX=fixed',
      });
      final progress = <(int, int, String)>[];
      final report = await SentinelService(apiService: api).autoFixAll(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
        onProgress: (i, count, id) => progress.add((i, count, id)),
      );
      expect(progress, [(0, 3, 'dns'), (1, 3, 'bypass'), (2, 3, 'firewall')]);
      expect(report.steps.map((s) => s.id), ['dns', 'bypass', 'firewall']);
      expect(report.steps.map((s) => s.status), [
        SentinelFixStatus.fixed,
        SentinelFixStatus.fixed,
        SentinelFixStatus.fixed,
      ]);
      expect(report.steps[1].detail, 'mihomo');
      expect(report.fixedCount, 3);
      expect(report.failedCount, 0);
      expect(report.skippedCount, 0);
      expect(report.allFixed, isTrue);
      expect(api.scripts, hasLength(3));
    });

    test('a failing step does not stop the remaining repairs', () async {
      final api = _FixApi({
        'dns': 'OWS_FIX=failed',
        'bypass': 'OWS_FIX=fixed:sing-box',
        'firewall': 'OWS_FIX=skipped',
      });
      final report = await SentinelService(
        apiService: api,
      ).autoFixAll(routerIp: 'router', sysauth: 'session', useHttps: false);
      expect(report.steps.map((s) => s.status), [
        SentinelFixStatus.failed,
        SentinelFixStatus.fixed,
        SentinelFixStatus.skipped,
      ]);
      expect(report.allFixed, isFalse);
      expect(report.fixedCount, 1);
      expect(report.failedCount, 1);
      expect(report.skippedCount, 1);
      expect(api.scripts, hasLength(3));
    });

    test('RPC denial fails only that step and the run continues', () async {
      final api = _FixApi({
        'dns': 'OWS_FIX=fixed',
        'bypass': 'OWS_FIX=fixed',
        'firewall': 'OWS_FIX=fixed',
      })..deniedStep = 'bypass';
      final report = await SentinelService(
        apiService: api,
      ).autoFixAll(routerIp: 'router', sysauth: 'session', useHttps: false);
      expect(report.steps[0].status, SentinelFixStatus.fixed);
      expect(report.steps[1].status, SentinelFixStatus.failed);
      expect(report.steps[1].detail, isNotNull);
      expect(report.steps[2].status, SentinelFixStatus.fixed);
      expect(api.scripts, hasLength(3));
    });

    test('a non-zero exit code is a failure, not a repair', () async {
      final api = _FixApi({
        'dns': 'OWS_FIX=fixed',
        'bypass': 'OWS_FIX=fixed',
        'firewall': 'OWS_FIX=fixed',
      })..exitCode = 1;
      final report = await SentinelService(
        apiService: api,
      ).autoFixAll(routerIp: 'router', sysauth: 'session', useHttps: false);
      expect(
        report.steps.every((s) => s.status == SentinelFixStatus.failed),
        isTrue,
      );
    });

    test(
      'a missing result marker is a failure, never a silent success',
      () async {
        final api = _FixApi({
          'dns': '',
          'bypass': 'OWS_FIX=fixed',
          'firewall': 'OWS_FIX=fixed',
        });
        final report = await SentinelService(
          apiService: api,
        ).autoFixAll(routerIp: 'router', sysauth: 'session', useHttps: false);
        expect(report.steps[0].status, SentinelFixStatus.failed);
        expect(report.steps[1].status, SentinelFixStatus.fixed);
      },
    );

    test('each step script is independent and bounded', () {
      for (final step in SentinelService.fixSteps) {
        expect(step.script, contains('OWS_FIX='));
        expect(step.script, isNot(contains('set -e')));
        expect(step.script.trimRight(), endsWith('exit 0'));
      }
    });
  });

  group('connectivity probe validation', () {
    test('a denied probe is an error, not six timeouts', () async {
      final api = _ProbeApi([6]);
      await expectLater(
        SentinelService(apiService: api).checkConnectivity(
          routerIp: 'router',
          sysauth: 'session',
          useHttps: false,
        ),
        throwsA(isA<RpcException>()),
      );
    });

    test('malformed or unconfirmed probes throw instead of guessing', () async {
      for (final response in <dynamic>[
        null,
        [0],
        [0, {}],
        [
          0,
          {'code': 1, 'stdout': ''},
        ],
        [
          0,
          {'code': 0},
        ],
      ]) {
        final api = _ProbeApi(response);
        await expectLater(
          SentinelService(apiService: api).checkConnectivity(
            routerIp: 'router',
            sysauth: 'session',
            useHttps: false,
          ),
          throwsA(anyOf(isA<RpcException>(), isA<StateError>())),
        );
      }
    });

    test('parses online, blocked and missing targets', () async {
      final api = _ProbeApi([
        0,
        {'code': 0, 'stdout': 'Google:online:123\nYouTube:blocked:0\n'},
      ]);
      final targets = await SentinelService(apiService: api).checkConnectivity(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
      );
      final google = targets.firstWhere((t) => t.name == 'Google');
      expect(google.status, SentinelStatus.online);
      expect(google.latencyMs, 123);
      final youtube = targets.firstWhere((t) => t.name == 'YouTube');
      expect(youtube.status, SentinelStatus.blocked);
      final telegram = targets.firstWhere((t) => t.name == 'Telegram');
      expect(telegram.status, SentinelStatus.timeout);
    });

    test('the probe survives BusyBox date without %N', () async {
      final api = _ProbeApi([
        0,
        {'code': 0, 'stdout': ''},
      ]);
      await SentinelService(apiService: api).checkConnectivity(
        routerIp: 'router',
        sysauth: 'session',
        useHttps: false,
      );
      final script = api.scripts.single;
      expect(script, contains('now_ms'));
      expect(script, contains('*[!0-9]*'));
      expect(script, contains('date +%s'));
    });
  });
}

/// Routes each fix step script to a canned marker output.
class _FixApi implements IApiService {
  _FixApi(this.outputs);
  final Map<String, String> outputs;
  String? deniedStep;
  int exitCode = 0;
  final scripts = <String>[];

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    final script = params.last;
    scripts.add(script);
    final step = SentinelService.fixSteps.firstWhere((s) => s.script == script);
    if (step.id == deniedStep) return [6];
    return [
      0,
      {'code': exitCode, 'stdout': outputs[step.id] ?? ''},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeApi implements IApiService {
  _ProbeApi(this.response);
  final dynamic response;
  final scripts = <String>[];

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    scripts.add(params.last);
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
