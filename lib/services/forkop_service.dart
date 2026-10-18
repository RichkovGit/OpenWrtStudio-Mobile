import 'dart:convert';
import 'package:luci_mobile/services/forkop_topology.dart';

import 'package:dio/dio.dart';
import 'package:luci_mobile/models/forkop_node.dart';
import 'package:luci_mobile/models/forkop_subscription.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';

class ForkopService {
  final IApiService apiService;
  final Dio dio;

  static bool _executionSucceeded(dynamic response) =>
      response is List &&
      response.length == 2 &&
      response[0] == 0 &&
      response[1] is Map &&
      response[1]['code'] == 0;

  ForkopService({required this.apiService, Dio? dioClient})
    : dio =
          dioClient ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 6),
            ),
          );

  Future<List<ForkopNode>> fetchNodes({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    int controllerPort = 9090,
    String? secret,
  }) async {
    Map proxies = {};
    Map config = {};
    final caches = <Map<String, dynamic>>[];
    try {
      final response = await dio.get<dynamic>(
        Uri(
          scheme: 'http',
          host: routerIp,
          port: controllerPort,
          path: '/proxies',
        ).toString(),
        options: Options(
          headers: {
            if (secret != null && secret.isNotEmpty)
              'Authorization': 'Bearer $secret',
          },
        ),
      );
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (response.statusCode == 200 && data is Map && data['proxies'] is Map)
        proxies = data['proxies'] as Map;
    } catch (_) {
      /* Controller may be bound to router loopback. Use authenticated rpcd below. */
    }
    if (proxies.isEmpty) {
      try {
        final response = await apiService.systemExec(
          routerIp,
          sysauth,
          useHttps,
          command: '/bin/sh',
          params: ['-c', '/usr/bin/forkop clash_api get_proxies'],
        );
        if (_executionSucceeded(response)) {
          final data = jsonDecode(response[1]['stdout'] as String? ?? '{}');
          if (data is Map && data['proxies'] is Map)
            proxies = data['proxies'] as Map;
        }
      } catch (_) {}
    }
    try {
      final response = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: [
          '-c',
          r"printf '===CACHE===\n'; cat /var/run/forkop/section-cache/*.json 2>/dev/null || cat /etc/forkop/section-cache/*.json 2>/dev/null; printf '\n===CONFIG===\n'; cat /etc/sing-box/config.json 2>/dev/null",
        ],
      );
      if (response is List &&
          response.length == 2 &&
          response[0] == 0 &&
          response[1] is Map) {
        final output = response[1]['stdout'] as String? ?? '';
        final marker = output.indexOf('===CONFIG===');
        if (marker >= 0) {
          caches.addAll(
            ForkopTopology.documents(
              output.substring(0, marker).replaceFirst('===CACHE===', ''),
            ),
          );
          final docs = ForkopTopology.documents(
            output.substring(marker + '===CONFIG==='.length),
          );
          if (docs.isNotEmpty) config = docs.first;
        }
      }
    } catch (_) {}
    // Some rpcd accounts allow file.read but not file.exec.
    if (caches.isEmpty || config.isEmpty) {
      for (final path in [
        '/var/run/forkop/section-cache/main.json',
        '/etc/sing-box/config.json',
      ]) {
        if (path.endsWith('main.json') && caches.isNotEmpty ||
            path.endsWith('config.json') && config.isNotEmpty)
          continue;
        try {
          final response = await apiService.call(
            routerIp,
            sysauth,
            useHttps,
            object: 'file',
            method: 'read',
            params: {'path': path},
          );
          if (response is List &&
              response.length == 2 &&
              response[0] == 0 &&
              response[1] is Map) {
            final docs = ForkopTopology.documents(
              response[1]['data'] as String? ?? '',
            );
            if (path.endsWith('main.json')) {
              caches.addAll(docs);
            } else if (docs.isNotEmpty) {
              config = docs.first;
            }
          }
        } catch (_) {}
      }
    }
    return ForkopTopology.parse(
      proxies: proxies,
      config: config,
      caches: caches,
    );
  }

  /// Tests latency for a specific node via external controller or router ping
  Future<int?> testNodeDelay({
    required String routerIp,
    required String nodeName,
    int controllerPort = 9090,
    String? secret,
    String testUrl = 'http://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
  }) async {
    try {
      final url =
          'http://$routerIp:$controllerPort/proxies/${Uri.encodeComponent(nodeName)}/delay';
      final headers = <String, dynamic>{};
      if (secret != null && secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }

      final response = await dio.get<Map<String, dynamic>>(
        url,
        queryParameters: {'url': testUrl, 'timeout': timeoutMs},
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final delay = response.data!['delay'] as num?;
        return delay != null && delay > 0 ? delay.toInt() : null;
      }
    } catch (e) {
      Logger.debug('Delay test failed for $nodeName: $e');
    }
    return null;
  }

  /// Selects active node in a selector group (e.g. main-priority-main_priority-out or main-out).
  /// Automatically resolves Fallback 'GLOBAL' or empty group to the real selector group.
  Future<bool> selectNode({
    required String routerIp,
    required String nodeName,
    String? groupName,
    String? sysauth,
    bool useHttps = false,
    int controllerPort = 9090,
    String? secret,
  }) async {
    if (sysauth == null || sysauth.isEmpty) return false;
    final nodes = await fetchNodes(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      controllerPort: controllerPort,
      secret: secret,
    );
    final target = nodes.where((n) => n.name == nodeName).firstOrNull;
    final targetGroup = groupName != null && groupName.isNotEmpty
        ? groupName
        : target?.group;
    final parent = nodes.where((n) => n.name == targetGroup).firstOrNull;
    if (target == null ||
        parent == null ||
        !parent.hasLiveState ||
        !parent.canSelectMembers ||
        !parent.all.contains(nodeName) ||
        parent.name == nodeName)
      return false;

    final groupTag = parent.name;
    bool success = false;

    // 1. Try external controller REST API on :9090
    try {
      final url =
          'http://$routerIp:$controllerPort/proxies/${Uri.encodeComponent(groupTag)}';
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (secret != null && secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }

      final response = await dio.put<dynamic>(
        url,
        data: jsonEncode({'name': nodeName}),
        options: Options(headers: headers),
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        success = true;
      }
    } catch (e) {
      Logger.debug('Controller selectNode failed on :$controllerPort ($e)');
    }

    // 2. Fallback to native router CLI execution via ubus
    if (!success) {
      try {
        final safeTarget = nodeName.replaceAll("'", r"'\''");
        final safeGroup = groupTag.replaceAll("'", r"'\''");
        final script =
            "/usr/bin/forkop clash_api set_group_proxy '$safeGroup' '$safeTarget'";
        final res = await apiService.systemExec(
          routerIp,
          sysauth,
          useHttps,
          command: '/bin/sh',
          params: ['-c', script],
        );

        if (_executionSucceeded(res)) {
          success = true;
          Logger.info(
            'Router accepted selection command for $nodeName; checking state',
          );
        }
      } catch (e) {
        Logger.error('Router CLI fallback selectNode failed', e);
      }
    }

    if (!success) return false;
    final confirmed = await fetchNodes(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      controllerPort: controllerPort,
      secret: secret,
    );
    return confirmed.any(
      (n) => n.name == groupTag && n.now == nodeName && n.hasLiveState,
    );
  }

  /// Sets routing mode: 'Rule', 'Global', 'Direct'
  Future<bool> setRoutingMode({
    required String routerIp,
    required String mode,
    int controllerPort = 9090,
    String? secret,
  }) async {
    try {
      final url = 'http://$routerIp:$controllerPort/configs';
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (secret != null && secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }

      final response = await dio.patch<dynamic>(
        url,
        data: jsonEncode({'mode': mode}),
        options: Options(headers: headers),
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      Logger.error('Failed to set routing mode $mode', e);
      return false;
    }
  }

  /// Updates subscription by downloading profile on router
  Future<bool> updateSubscriptionOnRouter({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String subscriptionUrl,
    String targetPath = '/etc/mihomo/config.yaml',
  }) async {
    try {
      final trimmedUrl = subscriptionUrl.trim();
      if (!trimmedUrl.startsWith('http://') &&
          !trimmedUrl.startsWith('https://')) {
        Logger.error('Invalid subscription URL format: $subscriptionUrl');
        return false;
      }

      final safeUrl = "'${trimmedUrl.replaceAll("'", r"'\''")}'";
      final safeTarget = "'${targetPath.replaceAll("'", r"'\''")}'";
      final script =
          '''
curl -f -k -s -L $safeUrl -o $safeTarget.tmp && mv $safeTarget.tmp $safeTarget && /etc/init.d/mihomo restart >/dev/null 2>&1
''';
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', script],
      );
      return _executionSucceeded(res);
    } catch (e) {
      Logger.error('Failed to update subscription on router', e);
      return false;
    }
  }

  /// Fetches real subscriptions configured on the router via UCI forkop
  Future<List<ForkopSubscription>> fetchSubscriptions({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.call(
        routerIp,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'forkop'},
      );
      if (res is List && res.isNotEmpty && res[0] == 0 && res.length > 1) {
        final data = res[1] as Map<String, dynamic>?;
        final values = data?['values'] as Map<String, dynamic>?;
        if (values != null) {
          final subs = <ForkopSubscription>[];
          values.forEach((secName, secData) {
            if (secData is Map && secData['.type'] == 'subscription_url') {
              subs.add(
                ForkopSubscription(
                  id: secName,
                  name: (secData['node_prefix'] ?? secName).toString(),
                  url: (secData['url'] ?? '').toString(),
                  nodeCount: 0,
                  updatedAt: DateTime.now(),
                ),
              );
            }
          });
          return subs;
        }
      }
    } catch (e) {
      Logger.debug('Failed to fetch UCI subscriptions: $e');
    }
    return [];
  }

  /// Restarts ForkOP service on the router
  Future<bool> restartForkop({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: [
          '-c',
          '[ -x /usr/bin/forkop ] && /usr/bin/forkop restart || /etc/init.d/forkop restart',
        ],
      );
      return _executionSucceeded(res);
    } catch (e) {
      Logger.error('Failed to restart forkop', e);
      return false;
    }
  }

  /// Stops ForkOP service on the router
  Future<bool> stopForkop({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: [
          '-c',
          '[ -x /usr/bin/forkop ] && /usr/bin/forkop stop || /etc/init.d/forkop stop',
        ],
      );
      return _executionSucceeded(res);
    } catch (e) {
      Logger.error('Failed to stop forkop', e);
      return false;
    }
  }

  /// Starts ForkOP service on the router
  Future<bool> startForkop({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: [
          '-c',
          '[ -x /usr/bin/forkop ] && /usr/bin/forkop start || /etc/init.d/forkop start',
        ],
      );
      return _executionSucceeded(res);
    } catch (e) {
      Logger.error('Failed to start forkop', e);
      return false;
    }
  }

  /// Reloads ForkOP service configurations
  Future<bool> reloadForkop({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: [
          '-c',
          '[ -x /usr/bin/forkop ] && /usr/bin/forkop reload || /etc/init.d/forkop reload',
        ],
      );
      return _executionSucceeded(res);
    } catch (e) {
      Logger.error('Failed to reload forkop', e);
      return false;
    }
  }

  /// Toggles ForkOP autostart (enable / disable)
  Future<bool> toggleAutostart({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required bool enable,
  }) async {
    try {
      final cmd = enable ? 'enable' : 'disable';
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: [
          '-c',
          '[ -x /usr/bin/forkop ] && /usr/bin/forkop $cmd || /etc/init.d/forkop $cmd',
        ],
      );
      return _executionSucceeded(res);
    } catch (e) {
      Logger.error('Failed to toggle forkop autostart', e);
      return false;
    }
  }

  /// Fetches logs of ForkOP and Sing-box from router
  Future<String> fetchLogs({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', 'logread -e forkop -e sing-box | tail -n 120'],
      );
      if (res is List && res.length > 1) {
        final data = res[1] as Map<String, dynamic>?;
        final stdout = data?['stdout'] as String? ?? '';
        if (stdout.trim().isNotEmpty) return stdout.trim();
      }
      return 'Логи не найдены или служба не вела журнал.';
    } catch (e) {
      Logger.error('Failed to fetch logs', e);
      return 'Ошибка получения логов: $e';
    }
  }

  /// Reads Sing-box configuration from router (/etc/sing-box/config.json)
  Future<String> fetchSingboxConfig({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.call(
        routerIp,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': '/etc/sing-box/config.json'},
      );
      if (res is List && res.isNotEmpty && res[0] == 0 && res.length > 1) {
        final fileData = res[1] as Map<String, dynamic>?;
        final content = fileData?['data'] as String?;
        if (content != null && content.isNotEmpty) {
          return content;
        }
      }
      final execRes = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', 'cat /etc/sing-box/config.json'],
      );
      if (execRes is List && execRes.length > 1) {
        final data = execRes[1] as Map<String, dynamic>?;
        return data?['stdout'] as String? ?? '{}';
      }
      return '{}';
    } catch (e) {
      Logger.error('Failed to read sing-box config', e);
      return 'Ошибка чтения конфигурации: $e';
    }
  }
}
