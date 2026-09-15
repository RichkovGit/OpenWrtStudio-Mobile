import 'dart:async';
import 'dart:io';
import 'package:luci_mobile/models/usb_models.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/utils/logger.dart';

class RouterDiscoveryService {
  final IApiService? _apiService;

  RouterDiscoveryService({IApiService? apiService}) : _apiService = apiService;

  IApiService get apiService => _apiService ?? ServiceFactory.apiService;

  List<String> get defaultCandidates => candidates;

  static const List<String> candidates = [
    '192.168.10.1',
    '192.168.1.1',
    '192.168.0.1',
    '192.168.8.1',
    '192.168.2.1',
    '192.168.31.1',
    'openwrt.lan',
  ];

  Future<DiscoveredRouterInfo?> discoverAndAuthenticate({
    required String username,
    required String password,
    void Function(String status)? onProgress,
  }) async {
    onProgress?.call('Поиск активного роутера в сети...');

    for (final ip in defaultCandidates) {
      try {
        onProgress?.call('Проверка $ip...');
        // 1. Fast socket reachability test on port 80 or 443
        final isPortOpen =
            await _checkSocket(ip, 80, 500) || await _checkSocket(ip, 443, 500);
        if (!isPortOpen) continue;

        onProgress?.call('Авторизация на $ip...');
        // 2. Try auth
        String token = '';
        try {
          token = await apiService.login(ip, username, password, false);
        } catch (_) {}

        if (token.isNotEmpty) {
          // Success! Fetch board info
          var model = 'OpenWrt Router';
          var hostname = 'OpenWrt';
          var release = '';

          try {
            final dynamic res = await apiService.call(
              ip,
              token,
              false,
              object: 'system',
              method: 'board',
            );
            if (res is List &&
                res.length >= 2 &&
                res[0] == 0 &&
                res[1] is Map) {
              final data = res[1] as Map;
              model = data['model']?.toString() ?? model;
              hostname = data['hostname']?.toString() ?? hostname;
              release = data['release']?['description']?.toString() ?? '';
            }
          } catch (_) {}

          return DiscoveredRouterInfo(
            ipAddress: ip,
            hostname: hostname,
            model: model,
            firmware: release,
            authSucceeded: true,
            statusMessage: 'Успешно найден: $hostname ($model)',
          );
        } else {
          // Web port open, router reached but not yet logged in
          return DiscoveredRouterInfo(
            ipAddress: ip,
            hostname: 'OpenWrt ($ip)',
            model: 'OpenWrt Router',
            authSucceeded: false,
            statusMessage: 'Роутер найден по адресу $ip. Введите пароль.',
          );
        }
      } catch (e) {
        Logger.debug('Discovery check failed for $ip: $e');
      }
    }

    return null;
  }

  Future<bool> _checkSocket(String host, int port, int timeoutMs) async {
    try {
      final socket = await Socket.connect(host, port,
          timeout: Duration(milliseconds: timeoutMs));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
