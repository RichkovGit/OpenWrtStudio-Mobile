import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/services/service_factory.dart';

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
    final router = appState.activeRouter;
    if (router == null) return;

    try {
      final res = await ServiceFactory.apiService.systemExec(
        router.ip, router.token ?? '', router.useHttps,
        command: '/sbin/logread',
        params: ['-e', _filter.isEmpty ? '' : _filter, '-l', '200'],
      );

      String content = '';
      if (res is List && res.length > 1 && res[1] is Map) {
        content = (res[1]['stdout'] ?? '').toString();
      }
      if (content.isEmpty) {
        // Fallback to dmesg
        final dmesg = await ServiceFactory.apiService.systemExec(
          router.ip, router.token ?? '', router.useHttps,
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
        title: const Text('Системный журнал'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Копировать всё',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _logContent));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Логи скопированы в буфер')));
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLogs),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Фильтр (sing-box, dnsmasq, kernel)...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (val) {
                _filter = val.trim();
              },
              onSubmitted: (_) => _fetchLogs(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _logContent.isEmpty ? 'Логи пусты' : _logContent,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.greenAccent),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
