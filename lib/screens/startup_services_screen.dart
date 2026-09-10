import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/services/service_factory.dart';

class StartupServicesScreen extends ConsumerStatefulWidget {
  const StartupServicesScreen({super.key});

  @override
  ConsumerState<StartupServicesScreen> createState() => _StartupServicesScreenState();
}

class _StartupServicesScreenState extends ConsumerState<StartupServicesScreen> {
  bool _loading = true;
  List<String> _services = [];

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    setState(() => _loading = true);
    final appState = ref.read(appStateProvider);
    final router = appState.activeRouter;
    if (router == null) return;

    try {
      final res = await ServiceFactory.apiService.systemExec(
        router.ip, router.token ?? '', router.useHttps,
        command: '/bin/ls',
        params: ['/etc/init.d'],
      );

      final list = <String>[];
      if (res is List && res.length > 1 && res[1] is Map) {
        final stdout = (res[1]['stdout'] ?? '').toString();
        list.addAll(stdout.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty));
      }
      if (mounted) {
        setState(() {
          _services = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(String svc, String action) async {
    final appState = ref.read(appStateProvider);
    final router = appState.activeRouter;
    if (router == null) return;

    await ServiceFactory.apiService.systemExec(
      router.ip, router.token ?? '', router.useHttps,
      command: '/etc/init.d/$svc',
      params: [action],
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Служба $svc: выполнено $action')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Службы автозапуска'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchServices),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _services.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final svc = _services[i];
                return ListTile(
                  leading: const Icon(Icons.settings_applications, color: Color(0xFF00D2FF)),
                  title: Text(svc, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.play_arrow, color: Colors.greenAccent), tooltip: 'Старт', onPressed: () => _runAction(svc, 'start')),
                      IconButton(icon: const Icon(Icons.restart_alt, color: Colors.orangeAccent), tooltip: 'Перезапустить', onPressed: () => _runAction(svc, 'restart')),
                      IconButton(icon: const Icon(Icons.stop, color: Colors.redAccent), tooltip: 'Остановить', onPressed: () => _runAction(svc, 'stop')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
