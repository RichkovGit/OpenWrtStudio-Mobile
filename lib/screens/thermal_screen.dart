import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/services/thermal_service.dart';

class ThermalScreen extends ConsumerStatefulWidget {
  const ThermalScreen({super.key});
  @override
  ConsumerState<ThermalScreen> createState() => _ThermalScreenState();
}

class _ThermalScreenState extends ConsumerState<ThermalScreen>
    with WidgetsBindingObserver {
  List<ThermalReading> _readings = [];
  String? _error;
  bool _loading = false;
  bool _foreground = true;
  int _generation = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _fetchTemps();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _foreground && (ModalRoute.of(context)?.isCurrent ?? true))
        _fetchTemps();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _fetchTemps();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }

  Future<void> _fetchTemps({bool newSession = false}) async {
    if (_loading && !newSession) return;
    final generation = ++_generation;
    final appState = ref.read(appStateProvider);
    final session = appState.currentSession;
    final api = appState.apiService;
    setState(() {
      _loading = true;
      _error = null;
      if (newSession) _readings = [];
    });
    List<ThermalReading> readings = [];
    String? error;
    try {
      if (session == null || api == null)
        throw StateError('Нет подключения к роутеру');
      readings = await ThermalService(api).read(
        ip: session.ipAddress,
        token: session.sysauth,
        useHttps: session.useHttps,
      );
    } catch (e) {
      error = 'Не удалось прочитать температуру: $e';
    }
    if (!mounted || generation != _generation) return;
    if (appState.currentSession != session) {
      await _fetchTemps(newSession: true);
      return;
    }
    setState(() {
      _readings = readings;
      _error = error;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appStateProvider.select((state) => state.currentSession), (
      _,
      _,
    ) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchTemps(newSession: true);
      });
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Датчики температуры'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _fetchTemps(),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && _readings.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _fetchTemps(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null) SelectableText(_error!),
                    if (_error == null && _readings.isEmpty)
                      const Text(
                        'Прошивка не предоставляет датчики температуры через thermal/hwmon. Значения недоступны.',
                      ),
                    for (final sensor in _readings)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.thermostat),
                          title: Text(sensor.label),
                          subtitle: Text(sensor.path),
                          trailing: Text(
                            sensor.celsius == null
                                ? 'N/A'
                                : '${sensor.celsius!.toStringAsFixed(1)} °C',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
