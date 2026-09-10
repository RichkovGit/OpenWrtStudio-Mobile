import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';

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

    try {
      final res = await appState.systemExec(
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
        title: const Text('Датчики температуры'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchTemps),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSensorCard('Процессор CPU', 'MediaTek MT7981B', _cpuTemp, Icons.memory),
                const SizedBox(height: 12),
                _buildSensorCard('Wi-Fi 2.4 GHz', 'MediaTek MT7976C (phy0)', _wifi0Temp, Icons.wifi),
                const SizedBox(height: 12),
                _buildSensorCard('Wi-Fi 5 GHz', 'MediaTek MT7976C (phy1)', _wifi1Temp, Icons.wifi_tethering),
              ],
            ),
    );
  }

  Widget _buildSensorCard(String title, String subtitle, double temp, IconData icon) {
    Color tempColor = Colors.green;
    if (temp >= 70) tempColor = Colors.orange;
    if (temp >= 80) tempColor = Colors.red;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: tempColor.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(icon, color: tempColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Text(
              '${temp.toStringAsFixed(1)} °C',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: tempColor),
            ),
          ],
        ),
      ),
    );
  }
}
