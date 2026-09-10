import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';

class ProcessesScreen extends ConsumerStatefulWidget {
  const ProcessesScreen({super.key});

  @override
  ConsumerState<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends ConsumerState<ProcessesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _processes = [];

  @override
  void initState() {
    super.initState();
    _fetchProcesses();
  }

  Future<void> _fetchProcesses() async {
    setState(() => _loading = true);
    final appState = ref.read(appStateProvider);

    try {
      final res = await appState.systemExec(
        command: '/bin/ps',
        params: ['-w'],
      );

      final list = <Map<String, dynamic>>[];
      if (res is List && res.length > 1 && res[1] is Map) {
        final stdout = (res[1]['stdout'] ?? '').toString();
        final lines = stdout.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        for (final line in lines.skip(1)) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            list.add({
              'pid': parts[0],
              'user': parts[1],
              'stat': parts[parts.length > 4 ? 3 : 2],
              'command': parts.sublist(parts.length > 4 ? 4 : 3).join(' '),
            });
          }
        }
      }
      if (mounted) {
        setState(() {
          _processes = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _killProcess(String pid, int signal, String actionName) async {
    final appState = ref.read(appStateProvider);
    await appState.systemExec(
      command: '/bin/kill',
      params: ['-$signal', pid],
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Процесс $pid: $actionName')));
    }
    await _fetchProcesses();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диспетчер процессов'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchProcesses),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _processes.isEmpty
              ? const Center(child: Text('Нет данных о процессах'))
              : ListView.separated(
                  itemCount: _processes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final p = _processes[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF1E293B),
                        child: Text(p['pid'], style: const TextStyle(fontSize: 11, color: Color(0xFF00D2FF))),
                      ),
                      title: Text(p['command'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Пользователь: ${p['user']} • Статус: ${p['stat']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      trailing: PopupMenuButton<int>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (sig) => _killProcess(p['pid'], sig, sig == 15 ? 'SIGTERM (завершение)' : 'SIGKILL (принудительно)'),
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 15, child: Text('Завершить (SIGTERM)')),
                          PopupMenuItem(value: 9, child: Text('Принудительно убить (SIGKILL)')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
