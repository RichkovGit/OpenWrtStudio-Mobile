import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';

class SystemLogsScreen extends ConsumerStatefulWidget {
  const SystemLogsScreen({super.key});

  @override
  ConsumerState<SystemLogsScreen> createState() => _SystemLogsScreenState();
}

class _SystemLogsScreenState extends ConsumerState<SystemLogsScreen> {
  bool _loading = true;
  String _logContent = '';
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _loading = true);
    final appState = ref.read(appStateProvider);

    try {
      final res = await appState.systemExec(
        command: '/sbin/logread',
        params: _filter.isEmpty ? ['-l', '200'] : ['-e', _filter, '-l', '200'],
      );

      String content = '';
      if (res is List && res.length > 1 && res[1] is Map) {
        content = (res[1]['stdout'] ?? '').toString();
      }
      if (content.isEmpty) {
        // Fallback to dmesg
        final dmesg = await appState.systemExec(
          command: '/bin/dmesg',
          params: [],
        );
        if (dmesg is List && dmesg.length > 1 && dmesg[1] is Map) {
          content = (dmesg[1]['stdout'] ?? '').toString();
        }
      }
      if (mounted) {
        setState(() {
          _logContent = content;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Системный журнал (Syslog)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Копировать лог',
            onPressed: _logContent.isEmpty ? null : () {
              Clipboard.setData(ClipboardData(text: _logContent));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Лог скопирован в буфер')));
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLogs),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Фильтр (например: dnsmasq, dropbear, clash)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _filter = '');
                          _fetchLogs();
                        },
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onSubmitted: (val) {
                setState(() => _filter = val.trim());
                _fetchLogs();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logContent.isEmpty
                    ? const Center(child: Text('Журнал пуст'))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: SelectableText(
                            _logContent,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
