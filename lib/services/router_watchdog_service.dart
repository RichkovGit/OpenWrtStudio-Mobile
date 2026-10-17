import 'dart:async';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/utils/logger.dart';

class RouterWatchdogService {
  static RouterWatchdogService? _instance;
  static RouterWatchdogService get instance =>
      _instance ??= RouterWatchdogService();
  RouterWatchdogService({IApiService? apiService}) : _injectedApi = apiService;

  final IApiService? _injectedApi;
  IApiService? _activeApi;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _isMonitoring = false;
  int _generation = 0;
  String? _routerIp;
  String? _sysauth;
  bool _useHttps = false;
  Duration? _interval;
  bool get isMonitoring => _isMonitoring;

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
    if (routerIp.trim().isEmpty || sysauth.trim().isEmpty) {
      throw ArgumentError('Router address and session are required');
    }
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive');
    }
    if (_isMonitoring &&
        _routerIp == routerIp &&
        _sysauth == sysauth &&
        _useHttps == useHttps &&
        _interval == interval) {
      return;
    }
    stopMonitoring();
    _routerIp = routerIp;
    _sysauth = sysauth;
    _useHttps = useHttps;
    _interval = interval;
    _activeApi = _injectedApi ?? ServiceFactory.apiService;
    _isMonitoring = true;
    Logger.info('RouterWatchdogService started monitoring on $routerIp');

    final generation = _generation;
    _timer = Timer.periodic(interval, (_) => _schedulePoll(generation));
    _schedulePoll(generation);
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _isMonitoring = false;
    _generation++;
    _routerIp = null;
    _sysauth = null;
    _activeApi = null;
    _lastWanOnline = null;
    _lastForkopOnline = null;
    _lastHighTemp = null;
    _lastRouterOnline = null;
  }

  bool _isCurrent(int generation) => _isMonitoring && generation == _generation;

  void _schedulePoll(int generation) {
    if (!_isCurrent(generation) || _inFlight != null) return;
    final poll = _checkHealth(
      generation,
      _activeApi!,
      _routerIp!,
      _sysauth!,
      _useHttps,
    );
    _inFlight = poll;
    unawaited(
      poll.whenComplete(() {
        if (identical(_inFlight, poll)) _inFlight = null;
        // A replacement login waits for the old probe, without parallel RPCs.
        if (_isMonitoring && generation != _generation) {
          _schedulePoll(_generation);
        }
      }),
    );
  }

  Future<void> _notifyCurrent(
    int generation, {
    required int id,
    required String title,
    required String message,
  }) async {
    if (!_isCurrent(generation)) return;
    await NotificationService.showNotification(
      id: id,
      title: title,
      message: message,
    );
  }

  static Map? _rpcData(dynamic response, {bool execution = false}) {
    if (response is! List ||
        response.length != 2 ||
        response[0] != 0 ||
        response[1] is! Map) {
      return null;
    }
    final data = response[1] as Map;
    return execution && data['code'] != 0 ? null : data;
  }

  Future<void> _checkHealth(
    int generation,
    IApiService api,
    String routerIp,
    String sysauth,
    bool useHttps,
  ) async {
    // 1. Check router connectivity
    bool routerReachable = false;
    try {
      final boardRes = await api
          .call(routerIp, sysauth, useHttps, object: 'system', method: 'board')
          .timeout(const Duration(seconds: 5));
      routerReachable = _rpcData(boardRes)?.isNotEmpty == true;
    } catch (_) {
      routerReachable = false;
    }

    if (!_isCurrent(generation)) return;
    if (!routerReachable) {
      if (_lastRouterOnline != false) {
        _lastRouterOnline = false;
        await _notifyCurrent(
          generation,
          id: 1001,
          title: '❌ Роутер недоступен',
          message: 'Потеряна связь с $routerIp. Проверьте питание или Wi-Fi.',
        );
      }
      return;
    } else {
      if (_lastRouterOnline == false) {
        _lastRouterOnline = true;
        await _notifyCurrent(
          generation,
          id: 1001,
          title: '✅ Роутер снова в сети',
          message: 'Связь с $routerIp успешно восстановлена.',
        );
      }
      if (!_isCurrent(generation)) return;
      _lastRouterOnline = true;
    }
    if (!_isCurrent(generation)) return;

    // 2. Check WAN status
    try {
      final netRes = await api
          .call(
            routerIp,
            sysauth,
            useHttps,
            object: 'network.interface.wan',
            method: 'status',
          )
          .timeout(const Duration(seconds: 5));

      if (!_isCurrent(generation)) return;
      bool? wanUp;
      final data = _rpcData(netRes);
      if (data != null && data['up'] is bool) {
        wanUp = data['up'] == true;
      }

      if (wanUp == false && _lastWanOnline != false) {
        _lastWanOnline = false;
        await _notifyCurrent(
          generation,
          id: 1002,
          title: '⚠️ Интернет отключён',
          message: 'WAN-интерфейс не активен или кабель провайдера отключён.',
        );
      } else if (wanUp == true && _lastWanOnline == false) {
        _lastWanOnline = true;
        await _notifyCurrent(
          generation,
          id: 1002,
          title: '🌐 Интернет восстановлен',
          message: 'WAN-интерфейс снова подключён к сети.',
        );
      } else if (wanUp != null) {
        _lastWanOnline = wanUp;
      }
    } catch (e) {
      Logger.debug('Watchdog WAN check error: $e');
    }
    if (!_isCurrent(generation)) return;

    // 3. Check ForkOP / Sing-box
    try {
      final checkRes = await api
          .systemExec(
            routerIp,
            sysauth,
            useHttps,
            command: '/bin/sh',
            params: [
              '-c',
              'if [ -x /usr/bin/sing-box ] || [ -x /etc/init.d/sing-box ]; then pidof sing-box >/dev/null && echo UP || echo DOWN; else echo ABSENT; fi',
            ],
          )
          .timeout(const Duration(seconds: 5));

      if (!_isCurrent(generation)) return;
      final stdout = _rpcData(
        checkRes,
        execution: true,
      )?['stdout']?.toString().trim();
      bool? forkopRunning = stdout == 'UP'
          ? true
          : stdout == 'DOWN'
          ? false
          : null;

      if (forkopRunning == false && _lastForkopOnline != false) {
        _lastForkopOnline = false;
        await _notifyCurrent(
          generation,
          id: 1003,
          title: '🔴 Сбой ForkOP',
          message: 'Служба sing-box не запущена или аварийно остановлена.',
        );
      } else if (forkopRunning == true && _lastForkopOnline == false) {
        _lastForkopOnline = true;
        await _notifyCurrent(
          generation,
          id: 1003,
          title: '🛡️ ForkOP активен',
          message: 'Прокси-ядро sing-box работает в штатном режиме.',
        );
      } else if (forkopRunning != null) {
        _lastForkopOnline = forkopRunning;
      }
    } catch (_) {}
    if (!_isCurrent(generation)) return;

    // 4. Check CPU Thermal
    try {
      final tempRes = await api
          .systemExec(
            routerIp,
            sysauth,
            useHttps,
            command: '/bin/sh',
            params: [
              '-c',
              'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0',
            ],
          )
          .timeout(const Duration(seconds: 5));

      if (!_isCurrent(generation)) return;
      final data = _rpcData(tempRes, execution: true);
      if (data != null) {
        final raw = int.tryParse((data['stdout'] ?? '').toString().trim());
        if (raw == null) return;
        final tempC = raw.abs() >= 1000 ? raw / 1000.0 : raw.toDouble();
        if (tempC > 78.0 && _lastHighTemp != true) {
          _lastHighTemp = true;
          await _notifyCurrent(
            generation,
            id: 1004,
            title: '🌡️ Внимание: Перегрев роутера',
            message:
                'Температура процессора достигла ${tempC.toStringAsFixed(1)}°C!',
          );
        } else if (tempC < 70.0) {
          _lastHighTemp = false;
        }
      }
    } catch (_) {}
  }
}
