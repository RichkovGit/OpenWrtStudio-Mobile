import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';

class QuickCommand {
  final String title;
  final String description;
  final String command;
  final String icon;

  const QuickCommand({
    required this.title,
    required this.description,
    required this.command,
    required this.icon,
  });

  static List<QuickCommand> presets() => const [
    QuickCommand(
      title: 'Drop RAM Cache',
      description: 'Free up cached pagecache, dentries and inodes',
      command: 'sync; echo 3 > /proc/sys/vm/drop_caches && free -m',
      icon: 'memory',
    ),
    QuickCommand(
      title: 'Restart DNS / DHCP',
      description: 'Flush DNS caches and restart dnsmasq service',
      command: '/etc/init.d/dnsmasq restart',
      icon: 'dns',
    ),
    QuickCommand(
      title: 'Reload Firewall (FW4)',
      description: 'Re-apply nftables / iptables rules',
      command: 'fw4 reload 2>/dev/null || /etc/init.d/firewall reload',
      icon: 'security',
    ),
    QuickCommand(
      title: 'Show IP Routes',
      description: 'View current kernel routing tables',
      command: 'ip route show',
      icon: 'alt_route',
    ),
    QuickCommand(
      title: 'View System Log (logread)',
      description: 'Recent 50 lines from syslog buffer',
      command: 'logread | tail -n 50',
      icon: 'history_edu',
    ),
    QuickCommand(
      title: 'Kernel Messages (dmesg)',
      description: 'Recent kernel ring buffer messages',
      command: 'dmesg | tail -n 50',
      icon: 'terminal',
    ),
  ];
}

class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration executionTime;

  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.executionTime,
  });

  bool get isSuccess => exitCode == 0;
}

class CommandsService {
  final ApiServiceInterface apiService;

  CommandsService({required this.apiService});

  /// Executes any shell command on the router via ubus file.exec
  Future<CommandResult> execute({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String command,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', command],
      );
      sw.stop();

      final data = res is List && res.length > 1 ? res[1] as Map<String, dynamic>? : null;
      final code = (data?['code'] as num?)?.toInt() ?? 0;
      final stdout = data?['stdout'] as String? ?? '';
      final stderr = data?['stderr'] as String? ?? '';

      return CommandResult(
        exitCode: code,
        stdout: stdout,
        stderr: stderr,
        executionTime: sw.elapsed,
      );
    } catch (e) {
      sw.stop();
      Logger.error('Command execution failed', e);
      return CommandResult(
        exitCode: 1,
        stdout: '',
        stderr: e.toString(),
        executionTime: sw.elapsed,
      );
    }
  }
}
