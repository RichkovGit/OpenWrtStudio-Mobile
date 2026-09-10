import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/services/service_factory.dart';

class ThermalScreen extends ConsumerStatefulWidget {
  const ThermalScreen({super.key});

  @override
  ConsumerState<ThermalScreen> createState() => _ThermalScreenState();
}

class _ThermalScreenState extends ConsumerState<ThermalScreen> {
  bool _loading = true;
  double _cpuTemp = 61.3;
  double _wifi0Temp = 58.0;
  double _wifi1Temp = 58.0;

  @override
  void initState() {
    super.initState();
    _fetchTemps();
  }

  Future<void> _fetchTemps() async {
    setState(() => _loading = true);
    final appState = ref.read(appStateProvider);
    final router = appState.activeRouter;
    if (router == null) return;

    try {
      final res = await ServiceFactory.apiService.systemExec(
        router.ip, router.token ?? '', router.useHttps,
        command: '/bin/sh',
        params: ['-c', 'cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null'],
      );

      if (res is List && res.length > 1 && res[1] is Map) {
        final stdout = (res[1]['stdout'] ?? '').toString().trim();
        final lines = stdout.split('\n').map((l) => int.tryParse(l) ?? 0).toList();
        if (lines.isNotEmpty && lines[0] > 0) {
          _cpuTemp = lines[0] > 1000 ? lines[0] / 1000.0 : lines[0].toDouble();
        }
        if (lines.length > 1 && lines[1] > 0) {
          _wifi0Temp = lines[1] > 1000 ? lines[1] / 1000.0 : lines[1].toDouble();
        }
        if (lines.length > 2 && lines[2] > 0) {
          _wifi1Temp = lines[2] > 1000 ? lines[2] / 1000.0 : lines[2].toDouble();
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Температура датчиков'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchTemps),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSensorCard('Процессор (CPU Thermal)', _cpuTemp, Icons.memory),
                  const SizedBox(height: 12),
                  _buildSensorCard('Wi-Fi 2.4 GHz (Mt7915 Phy0)', _wifi0Temp, Icons.wifi),
                  const SizedBox(height: 12),
                  _buildSensorCard('Wi-Fi 5 GHz (Mt7915 Phy1)', _wifi1Temp, Icons.wifi_tethering),
                ],
              ),
            ),
    );
  }

  Widget _buildSensorCard(String title, double temp, IconData icon) {
    Color color = Colors.greenAccent;
    if (temp > 75) color = Colors.orangeAccent;
    if (temp > 85) color = Colors.redAccent;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(temp < 75 ? 'Температура в норме' : 'Повышенный нагрев', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        trailing: Text('${temp.toStringAsFixed(1)}°C', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }
}
