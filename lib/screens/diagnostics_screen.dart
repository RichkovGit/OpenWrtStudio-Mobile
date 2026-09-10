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
  final TextEditingController _targetCtrl = TextEditingController(text: '8.8.8.8');
  String _selectedTool = 'ping';
  String _output = '';
  bool _running = false;

  Future<void> _executeDiagnostic(String tool) async {
    final target = _targetCtrl.text.trim();
    if (target.isEmpty) return;

    setState(() {
      _running = true;
      _output = 'Выполняется $tool для $target...\n';
    });

    final appState = ref.read(appStateProvider);

    String cmd = '/bin/ping';
    List<String> args = ['-c', '4', target];

    if (tool == 'traceroute') {
      cmd = '/usr/bin/traceroute';
      args = ['-q', '1', '-w', '1', target];
    } else if (tool == 'nslookup') {
      cmd = '/usr/bin/nslookup';
      args = [target];
    }

    try {
      final res = await appState.systemExec(
        command: cmd,
        params: args,
      );

      String out = '';
      if (res is List && res.length > 1 && res[1] is Map) {
        out = (res[1]['stdout'] ?? '').toString();
        final err = (res[1]['stderr'] ?? '').toString();
        if (err.isNotEmpty) out += '\n' + err;
      }
      if (mounted) {
        setState(() {
          _output = out.isEmpty ? 'Нет ответа от утилиты' : out;
          _running = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _output = 'Ошибка выполнения: $e';
          _running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сетевая диагностика'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _output.isEmpty ? null : () {
              Clipboard.setData(ClipboardData(text: _output));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Результат скопирован')));
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _targetCtrl,
              decoration: InputDecoration(
                labelText: 'Хост или IP-адрес',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.network_ping),
                    label: const Text('Ping'),
                    onPressed: _running ? null : () => _executeDiagnostic('ping'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.alt_route),
                    label: const Text('Traceroute'),
                    onPressed: _running ? null : () => _executeDiagnostic('traceroute'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.dns),
                    label: const Text('NSLookup'),
                    onPressed: _running ? null : () => _executeDiagnostic('nslookup'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: _running
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: SelectableText(
                          _output.isEmpty ? 'Выберите утилиту выше для запуска диагностики...' : _output,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFE2E8F0)),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
