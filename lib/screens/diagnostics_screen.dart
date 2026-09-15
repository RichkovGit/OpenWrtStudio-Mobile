import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final TextEditingController _targetCtrl = TextEditingController(text: '1.1.1.1');
  final TextEditingController _packetSizeCtrl = TextEditingController(text: '56');
  final ScrollController _pageScroll = ScrollController();

  List<String> _interfaces = ['По умолчанию (Авто)'];
  String _selectedInterface = 'По умолчанию (Авто)';
  String _selectedPingCountPreset = '5';
  String _selectedTool = 'ping';
  String _output = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInterfaces();
    });
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    _packetSizeCtrl.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  Future<void> _loadInterfaces() async {
    try {
      final appState = ref.read(appStateProvider);
      final res = await appState.systemExec(
        command: '/bin/ls',
        params: ['/sys/class/net'],
      );

      if (res is List && res.length > 1 && res[1] is Map) {
        final stdout = (res[1]['stdout'] ?? '').toString();
        final rawIfaces = stdout
            .split(RegExp(r'\s+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != 'lo')
            .toList();

        if (rawIfaces.isNotEmpty && mounted) {
          setState(() {
            _interfaces = ['По умолчанию (Авто)', ...rawIfaces];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _executeDiagnostic(String tool) async {
    final target = _targetCtrl.text.trim();
    if (target.isEmpty) return;

    _selectedTool = tool;
    setState(() {
      _running = true;
      _output = 'Запуск $tool для $target...\n';
    });

    final appState = ref.read(appStateProvider);

    String cmd = '/bin/ping';
    List<String> args = [];

    if (tool == 'ping') {
      cmd = '/bin/ping';
      // Interface
      if (_selectedInterface != 'По умолчанию (Авто)') {
        args.addAll(['-I', _selectedInterface]);
      }
      // Count
      if (_selectedPingCountPreset != 'Бесконечно (∞)') {
        final cnt = int.tryParse(_selectedPingCountPreset) ?? 5;
        args.addAll(['-c', cnt.toString()]);
      }
      // Packet size
      final size = int.tryParse(_packetSizeCtrl.text.trim());
      if (size != null && size > 0 && size != 56) {
        args.addAll(['-s', size.toString()]);
      }
      args.add(target);
    } else if (tool == 'traceroute') {
      cmd = '/usr/bin/traceroute';
      if (_selectedInterface != 'По умолчанию (Авто)') {
        args.addAll(['-i', _selectedInterface]);
      }
      args.addAll(['-q', '1', '-w', '1', target]);
    } else if (tool == 'nslookup') {
      cmd = '/usr/bin/nslookup';
      args = [target];
    }

    try {
      final res = await appState.systemExec(
        command: cmd,
        params: args,
      );

      if (!mounted) return;

      String out = '';
      if (res is List && res.length > 1 && res[1] is Map) {
        out = (res[1]['stdout'] ?? '').toString();
        final err = (res[1]['stderr'] ?? '').toString();
        if (err.isNotEmpty) out += '\n' + err;
      }

      setState(() {
        if (_running) {
          _output = out.isEmpty ? 'Нет ответа от утилиты' : out;
          _running = false;
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_running) {
            _output = 'Ошибка выполнения: $e';
            _running = false;
          }
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _stopDiagnostic() async {
    setState(() {
      _running = false;
      _output += '\n⏹ Остановлено пользователем.\n';
    });
    _scrollToBottom();

    try {
      final appState = ref.read(appStateProvider);
      await appState.systemExec(
        command: '/usr/bin/killall',
        params: ['-INT', 'ping', 'traceroute'],
      );
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageScroll.hasClients) {
        _pageScroll.animateTo(
          _pageScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сетевая диагностика'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Скопировать результат',
            onPressed: _output.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _output));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Результат скопирован')),
                    );
                  },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          controller: _pageScroll,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Target input & Stop button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetCtrl,
                    decoration: InputDecoration(
                      labelText: 'Хост или IP-адрес',
                      hintText: '1.1.1.1, ya.ru',
                      isDense: true,
                      prefixIcon: const Icon(Icons.language, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (_running) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Стоп', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _stopDiagnostic,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // Interface, Packets count, Packet size
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Interface selector
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Интерфейс (-I):',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedInterface,
                                isDense: true,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                items: _interfaces.map((iface) {
                                  return DropdownMenuItem(
                                    value: iface,
                                    child: Text(
                                      iface,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: _running
                                    ? null
                                    : (val) {
                                        if (val != null) {
                                          setState(() => _selectedInterface = val);
                                        }
                                      },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Packet count preset
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Пакетов (-c):',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedPingCountPreset,
                                isDense: true,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                items: const [
                                  DropdownMenuItem(value: '5', child: Text('5')),
                                  DropdownMenuItem(value: '10', child: Text('10')),
                                  DropdownMenuItem(value: '20', child: Text('20')),
                                  DropdownMenuItem(value: '50', child: Text('50')),
                                  DropdownMenuItem(value: '100', child: Text('100')),
                                  DropdownMenuItem(value: 'Бесконечно (∞)', child: Text('Бесконечно (∞)')),
                                ],
                                onChanged: _running
                                    ? null
                                    : (val) {
                                        if (val != null) {
                                          setState(() => _selectedPingCountPreset = val);
                                        }
                                      },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Packet size
                        SizedBox(
                          width: 68,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Размер (-s):',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              TextField(
                                controller: _packetSizeCtrl,
                                keyboardType: TextInputType.number,
                                enabled: !_running,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '56',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D2FF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const Icon(Icons.network_ping, size: 16),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Ping', style: TextStyle(fontWeight: FontWeight.bold), maxLines: 1),
                    ),
                    onPressed: _running ? null : () => _executeDiagnostic('ping'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const Icon(Icons.alt_route, size: 16),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Traceroute', maxLines: 1),
                    ),
                    onPressed: _running ? null : () => _executeDiagnostic('traceroute'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const Icon(Icons.dns, size: 16),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('NSLookup', maxLines: 1),
                    ),
                    onPressed: _running ? null : () => _executeDiagnostic('nslookup'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Terminal output header
            Row(
              children: [
                const Icon(Icons.terminal, size: 18, color: Color(0xFF00D2FF)),
                const SizedBox(width: 6),
                Text(
                  'Вывод утилиты',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_output.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Очистить', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      setState(() {
                        _output = '';
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Terminal output container
            Container(
              constraints: const BoxConstraints(minHeight: 260),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: SelectableText(
                _output.isEmpty
                    ? 'Готов к диагностике. Выберите инструмент и нажмите кнопку выше.'
                    : _output,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFE2E8F0),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    ),
  );
  }
}
