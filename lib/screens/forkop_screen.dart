import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  List<ForkopSubscription> _subscriptions = [];
  String _activeMode = 'Rule';
  String? _selectedNodeName;
  bool _isLoading = false;
  bool _isTestingPing = false;
  bool _isActionRunning = false;
  String? _error;

  List<ForkopNode> get _groups => _nodes.where((n) => n.isGroup).toList();
  List<ForkopNode> get _regularNodes =>
      _nodes.where((n) => !n.isGroup).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

      final subs = await _forkopService.fetchSubscriptions(
        routerIp: router.activeAddress,
        sysauth: sysauth,
        useHttps: router.activeUseHttps,
      );

      // Find active node in selector groups
      String? activeName;
      for (final n in nodes) {
        if (n.isGroup && n.now != null && n.now!.isNotEmpty) {
          activeName = n.now;
          break;
        }
      }

      setState(() {
        _nodes = nodes;
        _subscriptions = subs;
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

  Future<void> _selectNode(String nodeName, {String? groupName}) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    if (router == null) return;

    final targetGroup = groupName ??
        _groups.firstOrNull?.name ??
        'GLOBAL';

    final success = await _forkopService.selectNode(
      routerIp: router.activeAddress,
      groupName: targetGroup,
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
      unawaited(_loadData());
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

  // ==========================================
  // Available Actions Handlers (Доступные действия)
  // ==========================================
  Future<void> _restartForkop() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() => _isActionRunning = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Перезапуск ForkOP на роутере...'),
        duration: Duration(seconds: 2),
      ),
    );

    final ok = await _forkopService.restartForkop(
      routerIp: router.activeAddress,
      sysauth: sysauth,
      useHttps: router.activeUseHttps,
    );

    if (mounted) {
      setState(() => _isActionRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'ForkOP успешно перезапущен' : 'Ошибка перезапуска ForkOP',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (ok) unawaited(_loadData());
    }
  }

  Future<void> _stopForkop() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() => _isActionRunning = true);
    final ok = await _forkopService.stopForkop(
      routerIp: router.activeAddress,
      sysauth: sysauth,
      useHttps: router.activeUseHttps,
    );

    if (mounted) {
      setState(() => _isActionRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Служба ForkOP остановлена' : 'Ошибка остановки ForkOP',
          ),
          backgroundColor: ok ? Colors.orange : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleAutostart(bool enable) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    setState(() => _isActionRunning = true);
    final ok = await _forkopService.toggleAutostart(
      routerIp: router.activeAddress,
      sysauth: sysauth,
      useHttps: router.activeUseHttps,
      enable: enable,
    );

    if (mounted) {
      setState(() => _isActionRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (enable ? 'Автостарт включен' : 'Автостарт отключен')
                : 'Ошибка настройки автостарта',
          ),
          backgroundColor: ok ? Colors.blue : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showLogsModal() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FutureBuilder<String>(
        future: _forkopService.fetchLogs(
          routerIp: router.activeAddress,
          sysauth: sysauth,
          useHttps: router.activeUseHttps,
        ),
        builder: (context, snapshot) {
          final content = snapshot.data ?? 'Загрузка системных логов...';
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.article_outlined, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'Логи ForkOP & Sing-box',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Скопировать',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Логи скопированы в буфер'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          child: SelectableText(
                            content,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSingboxConfigModal() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FutureBuilder<String>(
        future: _forkopService.fetchSingboxConfig(
          routerIp: router.activeAddress,
          sysauth: sysauth,
          useHttps: router.activeUseHttps,
        ),
        builder: (context, snapshot) {
          final content = snapshot.data ?? 'Чтение /etc/sing-box/config.json...';
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.settings, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'Конфигурация Sing-box',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Скопировать',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Конфигурация скопирована в буфер'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          child: SelectableText(
                            content,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCandidatesDialog(ForkopNode group) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group.displayTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: group.all.length,
            itemBuilder: (context, i) {
              final candidate = group.all[i];
              final isCurrent = group.now == candidate;
              return ListTile(
                dense: true,
                title: Text(
                  candidate,
                  style: TextStyle(
                    fontWeight:
                        isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                leading: Icon(
                  isCurrent ? Icons.check_circle : Icons.circle_outlined,
                  color: isCurrent ? Colors.green : Colors.grey,
                  size: 18,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _selectNode(candidate, groupName: group.name);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
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
          // Available Actions (Доступные действия) Card
          Card(
            margin: const EdgeInsets.fromLTRB(
              LuciSpacing.md,
              LuciSpacing.md,
              LuciSpacing.md,
              LuciSpacing.xs,
            ),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: LuciCardStyles.standardRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(LuciSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flash_on, color: Colors.amber, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Доступные действия',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_isActionRunning)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 1. Перезапустить Forkop (зеленая)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF48BB78),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _isActionRunning ? null : _restartForkop,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text(
                          'Перезапустить Forkop',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 2. Остановить Forkop (красная)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7F1D1D),
                          foregroundColor: const Color(0xFFFECACA),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _isActionRunning ? null : _stopForkop,
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: const Text(
                          'Остановить Forkop',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 3. Отключить автостарт (бордовая)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF581C1C),
                          foregroundColor: const Color(0xFFFDE8E8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed:
                            _isActionRunning ? null : () => _toggleAutostart(false),
                        icon: const Icon(Icons.pause_circle_outline, size: 16),
                        label: const Text(
                          'Отключить автостарт',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 4. Получить глобальную проверку (синяя)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _isTestingPing ? null : _testAllNodes,
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text(
                          'Получить глобальную проверку',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 5. Посмотреть логи (синяя)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _showLogsModal,
                        icon: const Icon(Icons.article_outlined, size: 16),
                        label: const Text(
                          'Посмотреть логи',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 6. Показать sing-box конфигурацию (синяя)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _showSingboxConfigModal,
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text(
                          'Показать sing-box конфигурацию',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Routing Mode Card
          Card(
            margin: const EdgeInsets.symmetric(
              horizontal: LuciSpacing.md,
              vertical: LuciSpacing.xs,
            ),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: LuciCardStyles.standardRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LuciSpacing.md,
                vertical: LuciSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.hub, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedNodeName != null
                          ? 'Активный: $_selectedNodeName'
                          : 'Режим маршрутизации',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    children: ['Rule', 'Global', 'Direct'].map((m) {
                      final selected = _activeMode == m;
                      return ChoiceChip(
                        label: Text(m, style: const TextStyle(fontSize: 12)),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _setRoutingMode(m),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          // Tabs: Группы, Узлы, Подписки
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                text: 'Группы (${_groups.length})',
                icon: const Icon(Icons.account_tree_outlined, size: 20),
              ),
              Tab(
                text: 'Узлы (${_regularNodes.length})',
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
                      // ==========================================
                      // Tab 0: Groups (Группы выбора и URLTest)
                      // ==========================================
                      RefreshIndicator(
                        onRefresh: _loadData,
                        child: _groups.isEmpty
                            ? LayoutBuilder(
                                builder: (context, constraints) =>
                                    SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: const Center(
                                      child: Text('Нет доступных групп'),
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: LuciSpacing.md,
                                  vertical: LuciSpacing.sm,
                                ),
                                itemCount: _groups.length,
                                itemBuilder: (context, index) {
                                  final group = _groups[index];
                                  final isSelected =
                                      _selectedNodeName == group.name ||
                                      _selectedNodeName == group.now;
                                  final latColor = _getLatencyColor(
                                    group.latencyMs,
                                  );

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    elevation: isSelected ? 3 : 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: isSelected
                                          ? BorderSide(
                                              color: Colors.greenAccent.shade700,
                                              width: 2,
                                            )
                                          : BorderSide.none,
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        if (group.all.isNotEmpty) {
                                          _showCandidatesDialog(group);
                                        } else {
                                          _selectNode(group.name);
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    group.displayTitle,
                                                    style: theme
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.info_outline,
                                                    size: 20,
                                                    color: Colors.blue,
                                                  ),
                                                  onPressed: () =>
                                                      _showCandidatesDialog(
                                                    group,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme
                                                        .primaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    group.type.displayName,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: colorScheme
                                                          .onPrimaryContainer,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (group.latencyMs != null &&
                                                    group.latencyMs! > 0)
                                                  Text(
                                                    '${group.latencyMs}ms',
                                                    style: TextStyle(
                                                      color: latColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                const Spacer(),
                                                if (group.all.isNotEmpty)
                                                  Text(
                                                    '${group.all.length} узлов',
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (group.now != null &&
                                                group.now!.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.check_circle,
                                                    color: Colors.green,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'Активен: ${group.now}',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),

                      // ==========================================
                      // Tab 1: Regular Nodes list (Узлы)
                      // ==========================================
                      RefreshIndicator(
                        onRefresh: _loadData,
                        child: _regularNodes.isEmpty
                            ? LayoutBuilder(
                                builder: (context, constraints) =>
                                    SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: const Center(
                                      child: Text('Нет доступных узлов'),
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: LuciSpacing.md,
                                  vertical: LuciSpacing.sm,
                                ),
                                itemCount: _regularNodes.length,
                                itemBuilder: (context, index) {
                                  final node = _regularNodes[index];
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
                                        node.displayTitle,
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
                                                    final fullIdx =
                                                        _nodes.indexWhere(
                                                      (n) => n.name == node.name,
                                                    );
                                                    if (fullIdx >= 0) {
                                                      _nodes[fullIdx] = node
                                                          .copyWith(
                                                        latencyMs: delay,
                                                      );
                                                    }
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

                      // ==========================================
                      // Tab 2: Subscriptions
                      // ==========================================
                      RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(LuciSpacing.md),
                          children: [
                            if (_subscriptions.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Center(
                                  child: Text('Нет настроенных подписок'),
                                ),
                              )
                            else
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
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
