import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/protocol_item.dart';
import 'package:luci_mobile/services/protocol_service.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';

class ProtocolsScreen extends ConsumerStatefulWidget {
  const ProtocolsScreen({super.key});

  @override
  ConsumerState<ProtocolsScreen> createState() => _ProtocolsScreenState();
}

class _ProtocolsScreenState extends ConsumerState<ProtocolsScreen> {
  late ProtocolService _protocolService;
  List<ProtocolItem> _protocols = ProtocolItem.defaultList();
  bool _isLoading = false;
  String? _busyProtocolId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = ref.read(appStateProvider);
    if (appState.apiService != null) {
      _protocolService = ProtocolService(apiService: appState.apiService!);
      _scanProtocols();
    }
  }

  Future<void> _scanProtocols() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final items = await _protocolService.scanProtocols(
        routerIp: router.activeAddress,
        sysauth: sysauth,
        useHttps: router.activeUseHttps,
      );
      if (mounted) {
        setState(() {
          _protocols = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _controlService(ProtocolItem item, String action) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() {
      _busyProtocolId = item.id;
    });

    final success = await _protocolService.controlService(
      routerIp: router.activeAddress,
      sysauth: sysauth,
      useHttps: router.activeUseHttps,
      serviceName: item.serviceName,
      action: action,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Служба ${item.name}: команда $action выполнена'
                : 'Ошибка выполнения $action для ${item.name}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _scanProtocols();
      setState(() {
        _busyProtocolId = null;
      });
    }
  }

  Future<void> _installProtocol(ProtocolItem item) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() {
      _busyProtocolId = item.id;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Установка ${item.name}... Это может занять минуту.'),
        duration: const Duration(seconds: 4),
      ),
    );

    final success = await _protocolService.installProtocol(
      routerIp: router.activeAddress,
      sysauth: sysauth,
      useHttps: router.activeUseHttps,
      packageNames: item.packageNames,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Пакет ${item.name} успешно установлен!'
                : 'Ошибка установки ${item.name}',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _scanProtocols();
      setState(() {
        _busyProtocolId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: LuciAppBar(
        title: const Text('VPN и Протоколы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _scanProtocols,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _scanProtocols,
        child: _isLoading && _protocols.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(LuciSpacing.md),
                itemCount: _protocols.length,
                itemBuilder: (context, index) {
                  final item = _protocols[index];
                  final isBusy = _busyProtocolId == item.id;

                  Color statusColor;
                  String statusText;
                  if (item.isRunning) {
                    statusColor = Colors.green;
                    statusText = 'Работает';
                  } else if (item.isInstalled) {
                    statusColor = Colors.orange;
                    statusText = 'Остановлен';
                  } else {
                    statusColor = Colors.grey;
                    statusText = 'Не установлен';
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: item.isRunning
                          ? BorderSide(color: statusColor.withAlpha(120), width: 1.5)
                          : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(LuciSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: item.isRunning
                                    ? Colors.green.withAlpha(30)
                                    : colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  item.category == ProtocolCategory.vpn
                                      ? Icons.vpn_lock
                                      : item.category == ProtocolCategory.proxy
                                          ? Icons.shuffle
                                          : Icons.device_hub,
                                  color: item.isRunning ? Colors.green : colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.category.displayName,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withAlpha(30),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: statusColor.withAlpha(100)),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withAlpha(200),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (isBusy)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else if (!item.isInstalled)
                                FilledButton.tonalIcon(
                                  onPressed: () => _installProtocol(item),
                                  icon: const Icon(Icons.download, size: 18),
                                  label: const Text('Установить'),
                                )
                              else ...[
                                if (item.isRunning) ...[
                                  OutlinedButton(
                                    onPressed: () => _controlService(item, 'stop'),
                                    child: const Text('Стоп'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: () => _controlService(item, 'restart'),
                                    child: const Text('Перезапуск'),
                                  ),
                                ] else ...[
                                  FilledButton(
                                    onPressed: () => _controlService(item, 'start'),
                                    child: const Text('Запустить'),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
