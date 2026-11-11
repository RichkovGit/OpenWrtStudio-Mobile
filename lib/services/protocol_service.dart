import 'package:luci_mobile/services/protocol_installer.dart';
import 'package:luci_mobile/models/protocol_item.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/services/api_service.dart';

class ProtocolService {
  final IApiService apiService;

  ProtocolService({required this.apiService});

  // Package/service evidence and exact executable names are independent:
  // a manually started core does not need an init script or UCI frontend.
  static const scanScript = r'''
echo "===PKGS==="
if command -v apk >/dev/null 2>&1; then
  apk info 2>/dev/null
elif command -v opkg >/dev/null 2>&1; then
  opkg list-installed 2>/dev/null | grep -E "(forkop|amneziawg|wireguard|sing-box|mihomo|passwall|openvpn|tailscale|zerotier|xray)" | awk '{print $1}'
fi

echo "===BINS==="
for b in forkop /usr/bin/forkop awg awg-quick wg wg-quick sing-box mihomo clash passwall openvpn tailscale tailscaled zerotier-one zerotier-cli xray xray-core /etc/mihomo/mihomo; do
  if command -v "$b" >/dev/null 2>&1 || [ -x "$b" ]; then
    echo "$b"
  fi
done

echo "===SERVICES==="
for s in forkop amneziawg wireguard sing-box mihomo passwall openvpn tailscale zerotier xray; do
  if [ -x "/etc/init.d/$s" ]; then
    if "/etc/init.d/$s" status >/dev/null 2>&1; then
      echo "$s:running"
    else
      echo "$s:stopped"
    fi
  elif [ "$s" = "forkop" ] && [ -x /usr/bin/forkop ]; then
    if /usr/bin/forkop get_status 2>/dev/null | grep -q -i "running"; then
      echo "forkop:running"
    else
      echo "forkop:stopped"
    fi
  fi
done

echo "===MODULES==="
for m in amneziawg wireguard; do
  if [ -d "/sys/module/$m" ] || grep -q "^$m " /proc/modules 2>/dev/null; then
    echo "$m"
  fi
done

echo "===PROCS==="
# Read the executable, never a ps column or a configuration argument. BusyBox
# ps output can be truncated and the last argument is rarely the executable.
for proc in /proc/[0-9]*; do
  [ -d "$proc" ] || continue
  exe=$(readlink "$proc/exe" 2>/dev/null)
  if [ -n "$exe" ]; then
    exe=${exe##*/}
    exe=${exe%" (deleted)"}
  else
    # comm is available on routers without readlink or executable access.
    # All supported daemon names fit Linux's 15-character comm limit.
    exe=$(cat "$proc/comm" 2>/dev/null)
  fi
  case "$exe" in
    forkop|sing-box|mihomo|clash|passwall|openvpn|tailscaled|zerotier-one|xray|xray-core)
      printf '%s\n' "$exe";;
  esac
done
echo "===DONE==="
exit 0
''';

  static const _daemonNames = <String, Set<String>>{
    'forkop': {'forkop'},
    'sing-box': {'sing-box'},
    'mihomo': {'mihomo', 'clash'},
    'passwall': {'passwall'},
    'openvpn': {'openvpn'},
    'tailscale': {'tailscaled'},
    'zerotier': {'zerotier-one'},
    'xray': {'xray', 'xray-core'},
  };

  /// Scans installed packages and real running executables on the router.
  Future<List<ProtocolItem>> scanProtocols({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', scanScript],
      );

      validateRpcResult(res, object: 'file', method: 'exec');
      if (res is! List ||
          res.length != 2 ||
          res[1] is! Map ||
          res[1]['code'] != 0 ||
          res[1]['stdout'] is! String) {
        throw StateError('Роутер не подтвердил проверку протоколов');
      }
      final stdout = res[1]['stdout'] as String;
      if (!stdout.split('\n').contains('===DONE===')) {
        throw StateError('Проверка протоколов не завершена');
      }

      return _fromScanOutput(stdout);
    } on RpcException catch (error) {
      if (!error.isAccessDenied) rethrow;
      return _scanViaLuci(routerIp, sysauth, useHttps);
    }
  }

  static List<ProtocolItem> _fromScanOutput(
    String stdout, {
    bool installationComplete = true,
    bool servicesComplete = true,
    Set<String> unknownServices = const {},
  }) {
    final installedPkgs = <String>{};
    final foundBins = <String>{};
    final serviceStates = <String, String>{}; // 'running' or 'stopped'
    final kernelModules = <String>{};
    final runningProcs = <String>{};

    String currentSection = '';
    for (final line in stdout.split('\n').map((e) => e.trim())) {
      if (line.isEmpty) continue;
      if (line.startsWith('===') && line.endsWith('===')) {
        currentSection = line;
        continue;
      }

      switch (currentSection) {
        case '===PKGS===':
          installedPkgs.add(line.toLowerCase());
          break;
        case '===BINS===':
          foundBins.add(line.split('/').last.toLowerCase());
          break;
        case '===SERVICES===':
          final parts = line.split(':');
          if (parts.length == 2) {
            serviceStates[parts[0].toLowerCase()] = parts[1].toLowerCase();
          }
          break;
        case '===MODULES===':
          kernelModules.add(line.toLowerCase());
          break;
        case '===PROCS===':
          runningProcs.add(line.toLowerCase());
          break;
      }
    }

    final protocols = ProtocolItem.defaultList();
    // Merge findings with protocols
    return protocols.map((proto) {
      final id = proto.id.toLowerCase();

      // 1. Check if package or module installed
      final hasPkg = proto.packageNames.any(
        (p) => installedPkgs.contains(p.toLowerCase()),
      );
      final hasBin = proto.binaryNames.any(
        (b) => foundBins.contains(b.toLowerCase()),
      );
      final hasModule = kernelModules.contains(id);
      final hasService = serviceStates.containsKey(id);

      // 2. Check if running
      final serviceStatus = serviceStates[id];
      final procRunning = (_daemonNames[id] ?? const <String>{}).any(
        runningProcs.contains,
      );
      final isRunning = (serviceStatus == 'running') || procRunning;

      // An active service/process guarantees the protocol is installed
      final isInstalled =
          hasPkg || hasBin || hasModule || hasService || isRunning;

      return proto.copyWith(
        isInstalled: isInstalled,
        isRunning: isRunning,
        isEnabled: hasService,
        hasService: hasService,
        isServiceRunning: serviceStatus == 'running',
        installationVerified: installationComplete || isInstalled,
        serviceStateKnown: servicesComplete && !unknownServices.contains(id),
      );
    }).toList();
  }

  Future<List<ProtocolItem>> _scanViaLuci(
    String ip,
    String token,
    bool https,
  ) async {
    Future<Map> call(String object, String method) async {
      final result = validateRpcResult(
        await apiService.call(ip, token, https, object: object, method: method),
        object: object,
        method: method,
      );
      if (result.length != 2 || result[1] is! Map) {
        throw RpcException(
          object: object,
          method: method,
          detail: 'invalid response',
        );
      }
      return result[1] as Map;
    }

    // The same read-only method used by LuCI Status -> Processes. Its ACL is
    // independent of file.exec; do not grant shell access or retry a write.
    final data = (await call('luci', 'getProcessList'))['result'];
    final rows = data is List
        ? data
        : data is Map
        ? data.values.toList()
        : null;
    if (rows == null ||
        rows.isEmpty ||
        rows.any((row) => row is! Map || row['COMMAND'] is! String)) {
      throw StateError('LuCI не вернул достоверный список процессов');
    }
    final running = <String>{};
    final executable = RegExp(r"""^\s*(?:"([^"]+)"|'([^']+)'|(\S+))""");
    for (final row in rows) {
      final match = executable.firstMatch(row['COMMAND'] as String);
      final name = (match?.group(1) ?? match?.group(2) ?? match?.group(3) ?? '')
          .split('/')
          .last
          .toLowerCase();
      if (_daemonNames.values.any((names) => names.contains(name))) {
        running.add(name);
      }
    }
    final services = <String>[];
    final unknown = <String>{};
    var servicesComplete = false;
    try {
      final entries = await call('rc', 'list');
      if (entries.values.any((entry) => entry is! Map)) {
        throw StateError('invalid rc.list response');
      }
      servicesComplete = true;
      for (final proto in ProtocolItem.defaultList()) {
        final entry = entries[proto.serviceName];
        if (entry is! Map) continue;
        if (entry['running'] is! bool) unknown.add(proto.id);
        services.add(
          '${proto.id}:${entry['running'] == true ? 'running' : 'stopped'}',
        );
      }
    } catch (_) {
      // A denied optional service read must not discard permitted process data.
    }
    // Keep only recognized executable names. Never retain or log COMMAND,
    // which may contain credentials in unrelated process arguments.
    return _fromScanOutput(
      '===SERVICES===\n${services.join('\n')}\n===PROCS===\n${running.join('\n')}',
      installationComplete: false,
      servicesComplete: servicesComplete,
      unknownServices: unknown,
    );
  }

  static bool _commandSucceeded(dynamic response) {
    validateRpcResult(response, object: 'file', method: 'exec');
    return response is List &&
        response.length == 2 &&
        response[1] is Map &&
        response[1]['code'] == 0;
  }

  /// Controls service state (start, stop, restart)
  Future<bool> controlService({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String serviceName,
    required String action, // 'start', 'stop', 'restart'
  }) async {
    const allowedActions = {
      'start',
      'stop',
      'restart',
      'reload',
      'status',
      'enable',
      'disable',
    };
    final cleanAction = action.trim().toLowerCase();
    if (!allowedActions.contains(cleanAction)) return false;
    final cleanService = serviceName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    if (cleanService.isEmpty) return false;

    try {
      if (cleanService == 'forkop') {
        final res = await apiService.systemExec(
          routerIp,
          sysauth,
          useHttps,
          command: '/bin/sh',
          params: [
            '-c',
            '[ -x /usr/bin/forkop ] && /usr/bin/forkop $cleanAction || /etc/init.d/forkop $cleanAction',
          ],
        );
        return _commandSucceeded(res);
      }

      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/etc/init.d/$cleanService',
        params: [cleanAction],
      );
      return _commandSucceeded(res);
    } on RpcException catch (error) {
      if (error.isAccessDenied && cleanAction != 'status') {
        try {
          final result = validateRpcResult(
            await apiService.call(
              routerIp,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': cleanService, 'action': cleanAction},
            ),
            object: 'rc',
            method: 'init',
          );
          return result.length == 2 &&
              result[1] is Map &&
              result[1]['result'] == true;
        } catch (_) {
          return false;
        }
      }
      return false;
    } catch (e) {
      Logger.error('Failed to $cleanAction service $cleanService', e);
      return false;
    }
  }

  /// Safely switches active protocol by stopping conflicting proxy/bypass services
  /// before starting the target service.
  Future<bool> switchProtocol({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String targetServiceName,
    String? currentServiceName,
  }) async {
    try {
      // Validate the target before stopping anything. A core started from a
      // console can be observed, but cannot be controlled through init.d.
      final protocols = await scanProtocols(
        routerIp: routerIp,
        sysauth: sysauth,
        useHttps: useHttps,
      );
      final target = protocols
          .where((p) => p.serviceName == targetServiceName)
          .firstOrNull;
      const proxyServices = {'forkop', 'mihomo', 'passwall', 'sing-box'};
      final conflicts = protocols
          .where(
            (p) =>
                p.isRunning &&
                p.serviceName != targetServiceName &&
                (p.serviceName == currentServiceName ||
                    (proxyServices.contains(targetServiceName) &&
                        proxyServices.contains(p.serviceName))),
          )
          .toList();
      if (target == null ||
          !target.canControlService ||
          conflicts.any((p) => !p.canControlService)) {
        return false;
      }
      for (final other in conflicts) {
        final stopped = await controlService(
          routerIp: routerIp,
          sysauth: sysauth,
          useHttps: useHttps,
          serviceName: other.serviceName,
          action: 'stop',
        );
        if (!stopped) return false;
      }

      final started = await controlService(
        routerIp: routerIp,
        sysauth: sysauth,
        useHttps: useHttps,
        serviceName: targetServiceName,
        action: 'start',
      );
      return started;
    } catch (e) {
      Logger.error('Failed to switch protocol to $targetServiceName', e);
      return false;
    }
  }

  Future<bool> installProtocol({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required List<String> packageNames,
  }) async => (await ProtocolInstaller(apiService).install(
    routerIp: routerIp,
    sysauth: sysauth,
    useHttps: useHttps,
    groups: packageNames.map((p) => [p]).toList(),
  )).success;
}
