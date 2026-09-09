import 'package:luci_mobile/models/protocol_item.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';

class ProtocolService {
  final ApiServiceInterface apiService;

  ProtocolService({required this.apiService});

  /// Scans the router for installed protocols, active processes, and services.
  /// Supports both OpenWrt 24/25 (apk) and OpenWrt 23 (opkg).
  Future<List<ProtocolItem>> scanProtocols({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    final protocols = ProtocolItem.defaultList();

    // Comprehensive scan script ported from OpenWrtStudio v2.5.2
    const scanScript = r'''
echo "===PKGS==="
if command -v apk >/dev/null 2>&1; then
  apk info -e amneziawg* wireguard* sing-box* mihomo* passwall* openvpn* tailscale* zerotier* xray* 2>/dev/null
elif command -v opkg >/dev/null 2>&1; then
  opkg list-installed 2>/dev/null | grep -E "(amneziawg|wireguard|sing-box|mihomo|passwall|openvpn|tailscale|zerotier|xray)" | awk '{print $1}'
fi

echo "===BINS==="
for b in awg awg-quick wg wg-quick sing-box mihomo clash passwall openvpn tailscale tailscaled zerotier-one zerotier-cli xray /etc/mihomo/mihomo; do
  if command -v "$b" >/dev/null 2>&1 || [ -x "$b" ]; then
    echo "$b"
  fi
done

echo "===SERVICES==="
for s in amneziawg wireguard sing-box mihomo passwall openvpn tailscale zerotier xray; do
  if [ -f "/etc/init.d/$s" ]; then
    if "/etc/init.d/$s" status >/dev/null 2>&1; then
      echo "$s:running"
    else
      echo "$s:stopped"
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
ps -w 2>/dev/null | grep -E "(mihomo|sing-box|passwall|openvpn|tailscaled|zerotier-one|xray|awg|wireguard)" | grep -v grep | awk '{print $NF}'
''';

    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', scanScript],
      );

      final data = res is List && res.length > 1
          ? res[1] as Map<String, dynamic>?
          : null;
      final stdout = data?['stdout'] as String? ?? '';

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
            foundBins.add(line.toLowerCase());
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

      // Merge findings with protocols
      return protocols.map((proto) {
        final id = proto.id.toLowerCase();

        // 1. Check if package or module installed
        final hasPkg = proto.packageNames.any(
          (p) => installedPkgs.any((ip) => ip.contains(p.toLowerCase())),
        );
        final hasBin = proto.binaryNames.any(
          (b) => foundBins.any(
            (fb) =>
                fb.endsWith(b.toLowerCase()) || fb.contains(b.toLowerCase()),
          ),
        );
        final hasModule = kernelModules.contains(id);
        final hasService = serviceStates.containsKey(id);

        // 2. Check if running
        final serviceStatus = serviceStates[id];
        final procRunning = runningProcs.any((p) => p.contains(id));
        final isRunning = (serviceStatus == 'running') || procRunning;

        // An active service/process guarantees the protocol is installed
        final isInstalled =
            hasPkg || hasBin || hasModule || hasService || isRunning;

        return proto.copyWith(
          isInstalled: isInstalled,
          isRunning: isRunning,
          isEnabled: hasService,
        );
      }).toList();
    } catch (e) {
      Logger.error('Failed to scan router protocols via ubus', e);
      return protocols;
    }
  }

  /// Controls service state (start, stop, restart)
  Future<bool> controlService({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String serviceName,
    required String action, // 'start', 'stop', 'restart'
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/etc/init.d/$serviceName',
        params: [action],
      );
      return res != null;
    } catch (e) {
      Logger.error('Failed to $action service $serviceName', e);
      return false;
    }
  }

  /// Installs protocol packages using apk (OpenWrt 24/25) or opkg
  Future<bool> installProtocol({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required List<String> packageNames,
  }) async {
    if (packageNames.isEmpty) return false;
    final pkgs = packageNames.join(' ');
    final script =
        '''
if command -v apk >/dev/null 2>&1; then
  apk add $pkgs
elif command -v opkg >/dev/null 2>&1; then
  opkg update && opkg install $pkgs
fi
echo \$?
''';

    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', script],
      );
      final data = res is List && res.length > 1
          ? res[1] as Map<String, dynamic>?
          : null;
      final stdout = (data?['stdout'] as String? ?? '').trim();
      return stdout.endsWith('0');
    } catch (e) {
      Logger.error('Failed to install packages $pkgs', e);
      return false;
    }
  }
}
