import 'package:luci_mobile/models/sentinel_target.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';

class SentinelService {
  final ApiServiceInterface apiService;

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
    for (final t in targets) {
      probeScript.writeln('''
start_time=\$(date +%s%3N 2>/dev/null || date +%s)
if curl -s -k -m 3 -o /dev/null -w "%{http_code}" "https://${t.host}" >/dev/null 2>&1; then
  end_time=\$(date +%s%3N 2>/dev/null || date +%s)
  lat=\$((end_time - start_time))
  echo "${t.name}:online:\$lat"
elif nc -w 2 -z "${t.host}" 443 2>/dev/null; then
  echo "${t.name}:online:100"
elif ping -c 1 -W 2 "${t.host}" >/dev/null 2>&1; then
  echo "${t.name}:online:50"
else
  echo "${t.name}:blocked:0"
fi
''');
    }

    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', probeScript.toString()],
      );

      final data = res is List && res.length > 1
          ? res[1] as Map<String, dynamic>?
          : null;
      final stdout = data?['stdout'] as String? ?? '';
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
    } catch (e) {
      Logger.error('Failed to run Sentinel connectivity check', e);
      return targets;
    }
  }

  /// Automatically heals router connection by restarting DNS and proxy engines
  Future<bool> autoHeal({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    const healScript = r'''
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
      return res != null;
    } catch (e) {
      Logger.error('Failed to run AutoHeal', e);
      return false;
    }
  }
}
