import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/services/commands_service.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';

class CommandsScreen extends ConsumerStatefulWidget {
  const CommandsScreen({super.key});

  @override
  ConsumerState<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends ConsumerState<CommandsScreen> {
  late CommandsService _commandsService;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _consoleOutput = 'OpenWrt Terminal ready.\n';
  bool _isExecuting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = ref.read(appStateProvider);
    if (appState.apiService != null) {
      _commandsService = CommandsService(apiService: appState.apiService!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _runCommand(String command) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) {
      setState(() {
        _consoleOutput += '\n[ERROR] Роутер не подключен или нет сессии.';
      });
      return;
    }

    setState(() {
      _isExecuting = true;
      _consoleOutput += '\n\$ $command\n';
    });

    try {
      final res = await _commandsService.execute(
        routerIp: router.activeAddress,
        sysauth: sysauth,
        useHttps: router.activeUseHttps,
        command: command,
      );

      setState(() {
        if (res.stdout.isNotEmpty) {
          _consoleOutput += res.stdout;
          if (!res.stdout.endsWith('\n')) _consoleOutput += '\n';
        }
        if (res.stderr.isNotEmpty) {
          _consoleOutput += '[STDERR] ${res.stderr}\n';
        }
        _consoleOutput +=
            '[exit: ${res.exitCode}, time: ${res.executionTime.inMilliseconds}ms]\n';
        _isExecuting = false;
      });

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() {
        _consoleOutput += '[EXCEPTION] $e\n';
        _isExecuting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presets = QuickCommand.presets();

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Быстрые команды и терминал',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Очистить вывод',
            onPressed: () {
              setState(() {
                _consoleOutput = 'OpenWrt Terminal ready.\n';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Скопировать вывод',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _consoleOutput));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Вывод скопирован в буфер')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick Command Presets (horizontal chips)
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
              itemCount: presets.length,
              itemBuilder: (context, index) {
                final p = presets[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.terminal, size: 16),
                    label: Text(p.title),
                    onPressed: _isExecuting
                        ? null
                        : () => _runCommand(p.command),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Terminal console output box
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  _consoleOutput,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFF00FF66),
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Command Input Bar
          Padding(
            padding: const EdgeInsets.all(LuciSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isExecuting,
                    decoration: InputDecoration(
                      hintText: 'Введите команду (например: uptime)...',
                      prefixIcon: const Icon(Icons.chevron_right),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (val) {
                      final trimmed = val.trim();
                      if (trimmed.isNotEmpty) {
                        _controller.clear();
                        _runCommand(trimmed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isExecuting
                      ? null
                      : () {
                          final trimmed = _controller.text.trim();
                          if (trimmed.isNotEmpty) {
                            _controller.clear();
                            _runCommand(trimmed);
                          }
                        },
                  icon: _isExecuting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
