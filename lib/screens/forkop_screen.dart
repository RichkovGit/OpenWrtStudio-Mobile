import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/forkop_node.dart';
import 'package:luci_mobile/models/forkop_subscription.dart';
import 'package:luci_mobile/services/forkop_service.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';

class ForkopScreen extends ConsumerStatefulWidget {
  const ForkopScreen({super.key});

  @override
  ConsumerState<ForkopScreen> createState() => _ForkopScreenState();
}

class _ForkopScreenState extends ConsumerState<ForkopScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ForkopService _forkopService;

  List<ForkopNode> _nodes = [];
  final List<ForkopSubscription> _subscriptions = [];
  String _activeMode = 'Rule';
  String? _selectedNodeName;
  bool _isLoading = false;
  bool _isTestingPing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = ref.read(appStateProvider);
    if (appState.apiService != null) {
      _forkopService = ForkopService(apiService: appState.apiService!);
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final nodes = await _forkopService.fetchNodes(
        routerIp: router.activeAddress,
        sysauth: sysauth,
        useHttps: router.activeUseHttps,
      );

      // Find active node in selector
      String? activeName;
      for (final n in nodes) {
        if (n.isGroup && n.now != null) {
          activeName = n.now;
          break;
        }
      }

      setState(() {
        _nodes = nodes;
        if (activeName != null) {
          _selectedNodeName = activeName;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _testAllNodes() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    if (router == null) return;

    setState(() {
      _isTestingPing = true;
    });

    final updatedNodes = List<ForkopNode>.from(_nodes);
    for (int i = 0; i < updatedNodes.length; i++) {
      final node = updatedNodes[i];
      if (node.isGroup) continue;

      final delay = await _forkopService.testNodeDelay(
        routerIp: router.activeAddress,
        nodeName: node.name,
      );

      if (mounted) {
        setState(() {
          updatedNodes[i] = node.copyWith(latencyMs: delay);
        });
      }
    }

    if (mounted) {
      setState(() {
        _nodes = updatedNodes;
        _isTestingPing = false;
      });
    }
  }

  Future<void> _selectNode(String nodeName) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    if (router == null) return;

    // Find first selector group
    String groupName = 'PROXY';
    for (final n in _nodes) {
      if (n.isGroup) {
        groupName = n.name;
        break;
      }
    }

    final success = await _forkopService.selectNode(
      routerIp: router.activeAddress,
      groupName: groupName,
      nodeName: nodeName,
    );

    if (success && mounted) {
      setState(() {
        _selectedNodeName = nodeName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выбран узел: $nodeName'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setRoutingMode(String mode) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    if (router == null) return;

    final success = await _forkopService.setRoutingMode(
      routerIp: router.activeAddress,
      mode: mode,
    );

    if (success && mounted) {
      setState(() {
        _activeMode = mode;
      });
    }
  }

  void _showAddSubscriptionDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить подписку'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'My VPN Subscription',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'URL подписки',
                hintText: 'https://...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (urlController.text.trim().isNotEmpty) {
                final sub = ForkopSubscription(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim().isEmpty
                      ? 'Subscription ${_subscriptions.length + 1}'
                      : nameController.text.trim(),
                  url: urlController.text.trim(),
                  updatedAt: DateTime.now(),
                );
                setState(() {
                  _subscriptions.add(sub);
                });
                Navigator.pop(ctx);
                _updateSubscription(sub);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSubscription(ForkopSubscription sub) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Обновление подписки ${sub.name}...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final ok = await _forkopService.updateSubscriptionOnRouter(
      routerIp: router.activeAddress,
      sysauth: sysauth,
      useHttps: router.activeUseHttps,
      subscriptionUrl: sub.url,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Подписка успешно обновлена!' : 'Ошибка обновления подписки',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (ok) {
        unawaited(_loadData());
      }
    }
  }

  Color _getLatencyColor(int? latency) {
    if (latency == null || latency <= 0) return Colors.grey;
    if (latency < 150) return Colors.greenAccent.shade700;
    if (latency < 300) return Colors.orangeAccent.shade700;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: const LuciAppBar(title: 'ForkOP Proxies', showBack: true),
      body: Column(
        children: [
          // Mode & Action Bar
          Card(
            margin: const EdgeInsets.all(LuciSpacing.md),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: LuciCardStyles.standardRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(LuciSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hub, color: colorScheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedNodeName != null
                              ? 'Активный: $_selectedNodeName'
                              : 'Режим маршрутизации',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Mode Selector Chips
                      Wrap(
                        spacing: 6,
                        children: ['Rule', 'Global', 'Direct'].map((m) {
                          final selected = _activeMode == m;
                          return ChoiceChip(
                            label: Text(m),
                            selected: selected,
                            onSelected: (_) => _setRoutingMode(m),
                          );
                        }).toList(),
                      ),
                      const Spacer(),
                      // Ping all button
                      OutlinedButton.icon(
                        onPressed: _isTestingPing ? null : _testAllNodes,
                        icon: _isTestingPing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.speed, size: 18),
                        label: const Text('Пинг'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                text: 'Узлы (${_nodes.where((n) => !n.isGroup).length})',
                icon: const Icon(Icons.dns_outlined, size: 20),
              ),
              Tab(
                text: 'Подписки (${_subscriptions.length})',
                icon: const Icon(Icons.rss_feed, size: 20),
              ),
            ],
          ),

          // Tab content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Не удалось загрузить данные:\n$_error',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _loadData,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Nodes list
                      RefreshIndicator(
                        onRefresh: _loadData,
                        child: _nodes.isEmpty
                            ? const Center(child: Text('Нет доступных узлов'))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: LuciSpacing.md,
                                  vertical: LuciSpacing.sm,
                                ),
                                itemCount: _nodes.length,
                                itemBuilder: (context, index) {
                                  final node = _nodes[index];
                                  if (node.isGroup)
                                    return const SizedBox.shrink();

                                  final isSelected =
                                      _selectedNodeName == node.name;
                                  final latColor = _getLatencyColor(
                                    node.latencyMs,
                                  );

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: isSelected
                                          ? BorderSide(
                                              color: colorScheme.primary,
                                              width: 2,
                                            )
                                          : BorderSide.none,
                                    ),
                                    child: ListTile(
                                      onTap: () => _selectNode(node.name),
                                      leading: CircleAvatar(
                                        backgroundColor: isSelected
                                            ? colorScheme.primaryContainer
                                            : colorScheme
                                                  .surfaceContainerHighest,
                                        child: Icon(
                                          Icons.alt_route,
                                          color: isSelected
                                              ? colorScheme.primary
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      title: Text(
                                        node.name,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Text(node.type.displayName),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (node.latencyMs != null &&
                                              node.latencyMs! > 0)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: latColor.withAlpha(30),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: latColor.withAlpha(
                                                    100,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                '${node.latencyMs} ms',
                                                style: TextStyle(
                                                  color: latColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          else
                                            IconButton(
                                              icon: const Icon(
                                                Icons.bolt,
                                                size: 20,
                                              ),
                                              onPressed: () async {
                                                final appState = ref.read(
                                                  appStateProvider,
                                                );
                                                final router =
                                                    appState.selectedRouter;
                                                if (router == null) return;
                                                final delay =
                                                    await _forkopService
                                                        .testNodeDelay(
                                                          routerIp: router
                                                              .activeAddress,
                                                          nodeName: node.name,
                                                        );
                                                if (mounted) {
                                                  setState(() {
                                                    _nodes[index] = node
                                                        .copyWith(
                                                          latencyMs: delay,
                                                        );
                                                  });
                                                }
                                              },
                                            ),
                                          const SizedBox(width: 4),
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle,
                                              color: colorScheme.primary,
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Tab 2: Subscriptions
                      ListView(
                        padding: const EdgeInsets.all(LuciSpacing.md),
                        children: [
                          ..._subscriptions.map(
                            (sub) => Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      colorScheme.secondaryContainer,
                                  child: Icon(
                                    Icons.rss_feed,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                title: Text(
                                  sub.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  sub.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.sync),
                                  onPressed: () => _updateSubscription(sub),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _showAddSubscriptionDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Добавить подписку'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
