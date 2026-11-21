import 'package:luci_mobile/models/sentinel_fix_report.dart';
import 'package:luci_mobile/models/sentinel_target.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';

class SentinelService {
  final IApiService apiService;

  SentinelService({required this.apiService});

  /// Tests connectivity to targets from the router
  Future<List<SentinelTarget>> checkConnectivity({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    List<SentinelTarget>? customTargets,
  }) async {
    final targets = customTargets ?? SentinelTarget.defaultTargets();

    // Script to probe each target using curl or nc with timeout
    final probeScript = StringBuffer();
    // BusyBox date has no %N: `date +%s%3N` then prints a non-numeric
    // literal and the latency arithmetic fails. Fall back to whole seconds
    // scaled to milliseconds so the probe still reports a usable latency.
    probeScript.writeln(r'''
now_ms() {
  t=$(date +%s%3N 2>/dev/null)
  case "$t" in
    ''|*[!0-9]*) t=$(( $(date +%s) * 1000 ));;
  esac
  printf '%s' "$t"
}
''');
    for (final t in targets) {
      final host = t.host.trim();
      if (!RegExp(r'^[a-zA-Z0-9\.\-:_]+$').hasMatch(host)) continue;
      final safeHost = host.replaceAll("'", r"'\''");
      final safeName = t.name.replaceAll("'", r"'\''");

      probeScript.writeln('''
start_time=\$(now_ms)
if curl -s -k -m 3 -o /dev/null -w "%{http_code}" 'https://$safeHost' >/dev/null 2>&1; then
  end_time=\$(now_ms)
  lat=\$((end_time - start_time))
  echo '$safeName:online:'"\$lat"
elif nc -w 2 -z '$safeHost' 443 2>/dev/null; then
  echo '$safeName:online:100'
elif ping -c 1 -W 2 '$safeHost' >/dev/null 2>&1; then
  echo '$safeName:online:50'
else
  echo '$safeName:blocked:0'
fi
''');
    }

    final res = await apiService.systemExec(
      routerIp,
      sysauth,
      useHttps,
      command: '/bin/sh',
      params: ['-c', probeScript.toString()],
    );

    // A refused or malformed probe is an error, not "every target timed
    // out": reporting timeouts would blame the network for a permission
    // problem the user has to fix on the router.
    validateRpcResult(res, object: 'file', method: 'exec');
    if (res is! List ||
        res.length != 2 ||
        res[1] is! Map ||
        res[1]['code'] != 0 ||
        res[1]['stdout'] is! String) {
      throw StateError('Router did not confirm the connectivity check');
    }
    final stdout = res[1]['stdout'] as String;
    final lines = stdout
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    final statusMap = <String, (SentinelStatus, int?)>{};
    for (final line in lines) {
      final parts = line.split(':');
      if (parts.length >= 2) {
        final name = parts[0];
        final statusStr = parts[1];
        final lat = parts.length > 2 ? int.tryParse(parts[2]) : null;
        final status = statusStr == 'online'
            ? SentinelStatus.online
            : SentinelStatus.blocked;
        statusMap[name] = (status, lat != null && lat > 0 ? lat : null);
      }
    }

    final now = DateTime.now();
    return targets.map((t) {
      final entry = statusMap[t.name];
      if (entry != null) {
        return t.copyWith(
          status: entry.$1,
          latencyMs: entry.$2,
          lastChecked: now,
        );
      }
      return t.copyWith(status: SentinelStatus.timeout, lastChecked: now);
    }).toList();
  }

  /// Automatically heals router connection by restarting DNS and proxy engines
  Future<bool> autoHeal({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    const healScript = r'''
set -e
/etc/init.d/dnsmasq restart >/dev/null 2>&1
if [ -f /etc/init.d/mihomo ]; then
  /etc/init.d/mihomo restart >/dev/null 2>&1
elif [ -f /etc/init.d/sing-box ]; then
  /etc/init.d/sing-box restart >/dev/null 2>&1
elif [ -f /etc/init.d/passwall ]; then
  /etc/init.d/passwall restart >/dev/null 2>&1
fi
if command -v fw4 >/dev/null 2>&1; then
  fw4 reload >/dev/null 2>&1
fi
echo "healed"
''';

    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', healScript],
      );
      return res is List &&
          res.length == 2 &&
          res[0] == 0 &&
          res[1] is Map &&
          res[1]['code'] == 0;
    } catch (e) {
      Logger.error('Failed to run AutoHeal', e);
      return false;
    }
  }

  /// The repair steps a fix-all run applies, in order.
  ///
  /// Each script is independent and prints exactly one `OWS_FIX=` marker:
  /// `fixed`, `failed` or `skipped` (component absent), optionally with a
  /// detail after a colon. One failing step never stops the others.
  static const List<({String id, String script})> fixSteps = [
    (
      id: 'dns',
      script: r'''
if [ ! -x /etc/init.d/dnsmasq ]; then echo "OWS_FIX=skipped"; exit 0; fi
if /etc/init.d/dnsmasq restart >/dev/null 2>&1; then
  echo "OWS_FIX=fixed"
else
  echo "OWS_FIX=failed"
fi
exit 0
''',
    ),
    (
      id: 'bypass',
      script: r'''
svc=''
for s in forkop mihomo sing-box passwall shadowsocks-libev shadowsocks-rust hysteria tuic naiveproxy xray; do
  if [ -x "/etc/init.d/$s" ]; then svc="$s"; break; fi
done
if [ -z "$svc" ]; then echo "OWS_FIX=skipped"; exit 0; fi
if "/etc/init.d/$svc" restart >/dev/null 2>&1; then
  echo "OWS_FIX=fixed:$svc"
else
  echo "OWS_FIX=failed:$svc"
fi
exit 0
''',
    ),
    (
      id: 'firewall',
      script: r'''
if command -v fw4 >/dev/null 2>&1; then
  if fw4 reload >/dev/null 2>&1; then echo "OWS_FIX=fixed"; else echo "OWS_FIX=failed"; fi
elif [ -x /etc/init.d/firewall ]; then
  if /etc/init.d/firewall reload >/dev/null 2>&1; then echo "OWS_FIX=fixed"; else echo "OWS_FIX=failed"; fi
else
  echo "OWS_FIX=skipped"
fi
exit 0
''',
    ),
  ];

  /// Runs every applicable repair in sequence, reporting progress and a
  /// final per-step report of what was fixed and what was not.
  Future<SentinelFixReport> autoFixAll({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    void Function(int stepIndex, int stepCount, String stepId)? onProgress,
  }) async {
    final steps = <SentinelFixStep>[];
    for (var i = 0; i < fixSteps.length; i++) {
      final step = fixSteps[i];
      onProgress?.call(i, fixSteps.length, step.id);
      steps.add(
        await _runFixStep(
          routerIp: routerIp,
          sysauth: sysauth,
          useHttps: useHttps,
          step: step,
        ),
      );
    }
    return SentinelFixReport(steps);
  }

  Future<SentinelFixStep> _runFixStep({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required ({String id, String script}) step,
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', step.script],
      );
      validateRpcResult(res, object: 'file', method: 'exec');
      if (res is! List ||
          res.length != 2 ||
          res[1] is! Map ||
          res[1]['code'] != 0 ||
          res[1]['stdout'] is! String) {
        return SentinelFixStep(
          id: step.id,
          status: SentinelFixStatus.failed,
          detail: 'exit status not confirmed',
        );
      }
      final stdout = res[1]['stdout'] as String;
      final marker = RegExp(
        r'^OWS_FIX=(fixed|failed|skipped)(?::(.*))?$',
        multiLine: true,
      ).firstMatch(stdout);
      if (marker == null) {
        return SentinelFixStep(
          id: step.id,
          status: SentinelFixStatus.failed,
          detail: 'no result marker',
        );
      }
      final status = switch (marker.group(1)) {
        'fixed' => SentinelFixStatus.fixed,
        'skipped' => SentinelFixStatus.skipped,
        _ => SentinelFixStatus.failed,
      };
      final detail = marker.group(2)?.trim();
      return SentinelFixStep(
        id: step.id,
        status: status,
        detail: detail == null || detail.isEmpty ? null : detail,
      );
    } catch (e) {
      Logger.error('Fix-all step ${step.id} failed', e);
      return SentinelFixStep(
        id: step.id,
        status: SentinelFixStatus.failed,
        detail: e.toString(),
      );
    }
  }
}
