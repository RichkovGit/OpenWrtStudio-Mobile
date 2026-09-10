import 'dart:async';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/utils/logger.dart';

class RouterWatchdogService {
  static RouterWatchdogService? _instance;
  static RouterWatchdogService get instance => _instance ??= RouterWatchdogService._();
  RouterWatchdogService._();

  Timer? _timer;
  bool _isMonitoring = false;
  
  // Previous states to avoid alert storms
  bool? _lastWanOnline;
  bool? _lastForkopOnline;
  bool? _lastHighTemp;
  bool? _lastRouterOnline;

  void startMonitoring({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    Duration interval = const Duration(seconds: 30),
  }) {
    if (_isMonitoring) return;
    _isMonitoring = true;
    Logger.info('RouterWatchdogService started monitoring on $routerIp');

    _timer = Timer.periodic(interval, (_) async {
      await _checkHealth(routerIp, sysauth, useHttps);
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _isMonitoring = false;
    Logger.info('RouterWatchdogService stopped');
  }

  Future<void> _checkHealth(String routerIp, String sysauth, bool useHttps) async {
    final api = ServiceFactory.apiService;

    // 1. Check router connectivity
    bool routerReachable = false;
    try {
      final boardRes = await api.systemBoard(routerIp, sysauth, useHttps).timeout(const Duration(seconds: 5));
      routerReachable = boardRes != null && boardRes.isNotEmpty;
    } catch (_) {
      routerReachable = false;
    }

    if (!routerReachable) {
      if (_lastRouterOnline != false) {
        _lastRouterOnline = false;
        await NotificationService.showNotification(
          id: 1001,
          title: '❌ Роутер недоступен',
          message: 'Потеряна связь с $routerIp. Проверьте питание или Wi-Fi.',
        );
      }
      return;
    } else {
      if (_lastRouterOnline == false) {
        _lastRouterOnline = true;
        await NotificationService.showNotification(
          id: 1001,
          title: '✅ Роутер снова в сети',
          message: 'Связь с $routerIp успешно восстановлена.',
        );
      }
      _lastRouterOnline = true;
    }

    // 2. Check WAN status
    try {
      final netRes = await api.call(
        routerIp, sysauth, useHttps,
        object: 'network.interface.wan',
        method: 'status',
      ).timeout(const Duration(seconds: 5));

      bool wanUp = false;
      if (netRes is List && netRes.length > 1 && netRes[1] is Map) {
        final data = netRes[1] as Map<String, dynamic>;
        wanUp = data['up'] == true;
      }

      if (!wanUp && _lastWanOnline != false) {
        _lastWanOnline = false;
        await NotificationService.showNotification(
          id: 1002,
          title: '⚠️ Интернет отключён',
          message: 'WAN-интерфейс не активен или кабель провайдера отключён.',
        );
      } else if (wanUp && _lastWanOnline == false) {
        _lastWanOnline = true;
        await NotificationService.showNotification(
          id: 1002,
          title: '🌐 Интернет восстановлен',
          message: 'WAN-интерфейс снова подключён к сети.',
        );
      } else {
        _lastWanOnline = wanUp;
      }
    } catch (e) {
      Logger.debug('Watchdog WAN check error: $e');
    }

    // 3. Check ForkOP / Sing-box
    try {
      final checkRes = await api.systemExec(
        routerIp, sysauth, useHttps,
        command: '/bin/sh',
        params: ['-c', 'pidof sing-box >/dev/null && echo UP || echo DOWN'],
      ).timeout(const Duration(seconds: 5));

      String stdout = '';
      if (checkRes is List && checkRes.length > 1 && checkRes[1] is Map) {
        stdout = (checkRes[1]['stdout'] ?? '').toString().trim();
      }
      bool forkopRunning = stdout == 'UP';

      if (!forkopRunning && _lastForkopOnline != false) {
        _lastForkopOnline = false;
        await NotificationService.showNotification(
          id: 1003,
          title: '🔴 Сбой ForkOP',
          message: 'Служба sing-box не запущена или аварийно остановлена.',
        );
      } else if (forkopRunning && _lastForkopOnline == false) {
        _lastForkopOnline = true;
        await NotificationService.showNotification(
          id: 1003,
          title: '🛡️ ForkOP активен',
          message: 'Прокси-ядро sing-box работает в штатном режиме.',
        );
      } else {
        _lastForkopOnline = forkopRunning;
      }
    } catch (_) {}

    // 4. Check CPU Thermal
    try {
      final tempRes = await api.systemExec(
        routerIp, sysauth, useHttps,
        command: '/bin/sh',
        params: ['-c', 'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0'],
      ).timeout(const Duration(seconds: 5));

      if (tempRes is List && tempRes.length > 1 && tempRes[1] is Map) {
        final raw = int.tryParse((tempRes[1]['stdout'] ?? '0').toString().trim()) ?? 0;
        final tempC = raw > 1000 ? raw / 1000.0 : raw.toDouble();
        if (tempC > 78.0 && _lastHighTemp != true) {
          _lastHighTemp = true;
          await NotificationService.showNotification(
            id: 1004,
            title: '🌡️ Внимание: Перегрев роутера',
            message: 'Температура процессора достигла ${tempC.toStringAsFixed(1)}°C!',
          );
        } else if (tempC < 70.0) {
          _lastHighTemp = false;
        }
      }
    } catch (_) {}
  }
}
