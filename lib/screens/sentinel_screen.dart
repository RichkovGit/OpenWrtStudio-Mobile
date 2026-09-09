import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/sentinel_target.dart';
import 'package:luci_mobile/services/sentinel_service.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';

class SentinelScreen extends ConsumerStatefulWidget {
  const SentinelScreen({super.key});

  @override
  ConsumerState<SentinelScreen> createState() => _SentinelScreenState();
}

class _SentinelScreenState extends ConsumerState<SentinelScreen> {
  late SentinelService _sentinelService;
  List<SentinelTarget> _targets = SentinelTarget.defaultTargets();
  bool _isChecking = false;
  bool _isHealing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = ref.read(appStateProvider);
    if (appState.apiService != null) {
      _sentinelService = SentinelService(apiService: appState.apiService!);
      _checkHealth();
    }
  }

  Future<void> _checkHealth() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() {
      _isChecking = true;
    });

    try {
      final updated = await _sentinelService.checkConnectivity(
        routerIp: router.activeAddress,
        sysauth: sysauth,
        useHttps: router.activeUseHttps,
        customTargets: _targets,
      );
      if (mounted) {
        setState(() {
          _targets = updated;
          _isChecking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _runAutoHeal() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() {
      _isHealing = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Перезапуск DNS и служб обхода...'),
        duration: Duration(seconds: 3),
      ),
    );

    final ok = await _sentinelService.autoHeal(
      routerIp: router.activeAddress,
      sysauth: sysauth,
      useHttps: router.activeUseHttps,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Автовосстановление выполнено!' : 'Ошибка автовосстановления',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _isHealing = false;
      });
      await _checkHealth();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final onlineCount = _targets
        .where((t) => t.status == SentinelStatus.online)
        .length;
    final totalCount = _targets.length;
    final allGood = onlineCount == totalCount;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Sentinel Watchdog',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isChecking ? null : _checkHealth,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _checkHealth,
        child: ListView(
          padding: const EdgeInsets.all(LuciSpacing.md),
          children: [
            // Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: LuciCardStyles.standardRadius,
                side: BorderSide(
                  color: allGood
                      ? Colors.green.withAlpha(120)
                      : Colors.orange.withAlpha(120),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(LuciSpacing.md),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: allGood
                              ? Colors.green.withAlpha(30)
                              : Colors.orange.withAlpha(30),
                          child: Icon(
                            allGood
                                ? Icons.verified_user
                                : Icons.warning_amber_rounded,
                            color: allGood ? Colors.green : Colors.orange,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                allGood
                                    ? 'Туннелирование активно'
                                    : 'Обнаружены сбои связности',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$onlineCount из $totalCount контрольных сервисов доступны',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isChecking ? null : _checkHealth,
                            icon: _isChecking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.speed, size: 18),
                            label: const Text('Диагностика'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isHealing ? null : _runAutoHeal,
                            icon: _isHealing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.healing, size: 18),
                            label: const Text('Автохил'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Контрольные узлы проверки',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),

            ..._targets.map((t) {
              Color statusColor;
              IconData statusIcon;
              switch (t.status) {
                case SentinelStatus.online:
                  statusColor = Colors.green;
                  statusIcon = Icons.check_circle;
                  break;
                case SentinelStatus.blocked:
                  statusColor = Colors.red;
                  statusIcon = Icons.block;
                  break;
                case SentinelStatus.timeout:
                  statusColor = Colors.orange;
                  statusIcon = Icons.timer_off;
                  break;
                default:
                  statusColor = Colors.grey;
                  statusIcon = Icons.help_outline;
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withAlpha(25),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  title: Text(
                    t.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(t.host),
                  trailing: t.latencyMs != null && t.latencyMs! > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${t.latencyMs} ms',
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : Text(
                          t.status.displayName,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
