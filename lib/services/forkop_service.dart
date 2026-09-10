import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:luci_mobile/models/forkop_node.dart';
import 'package:luci_mobile/models/forkop_subscription.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';

class ForkopService {
  final IApiService apiService;
  final Dio dio;

  ForkopService({required this.apiService, Dio? dioClient})
    : dio =
          dioClient ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 6),
            ),
          );

  static final Map<String, String> _knownGroupLabels = {
    'main-priority-main_priority-out': 'Приоритет: Blanc -> Stealth -> Free',
    'main-urltest-blanc_urltest-out': 'Авто Blanc (Основной)',
    'main-urltest-stealth_urltest-out': 'Авто Stealth (Запасной)',
    'main-urltest-free_urltest-out': 'Авто Фри (Резерв)',
    'GLOBAL': 'GLOBAL (Общий)',
    'main-out': 'Основной селектор',
  };

  /// Attempts to fetch nodes from Mihomo / Clash Meta External Controller REST API
  /// or falls back to querying the router via ubus systemExec.
  Future<List<ForkopNode>> fetchNodes({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    int controllerPort = 9090,
    String? secret,
  }) async {
    // 1. Try Sing-box / Mihomo / Clash external controller API on port 9090 (always HTTP)
    try {
      final url = 'http://$routerIp:$controllerPort/proxies';
      final headers = <String, dynamic>{};
      if (secret != null && secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }

      final response = await dio.get<dynamic>(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> body = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);
        final proxiesMap = body['proxies'];
        if (proxiesMap is Map && proxiesMap.isNotEmpty) {
          final nodes = <ForkopNode>[];
          proxiesMap.forEach((name, data) {
            if (data is Map) {
              final nodeName = name.toString();
              var rawType = data['type']?.toString();
              if (nodeName.contains('priority') ||
                  (rawType != null &&
                      rawType.toLowerCase().contains('priority'))) {
                rawType = 'priority';
              }
              final label = _knownGroupLabels[nodeName];
              final node = ForkopNode.fromJson({
                ...Map<String, dynamic>.from(data),
                'name': nodeName,
                'label': label,
                if (rawType != null) 'type': rawType,
              });
              nodes.add(node);
            }
          });
          if (nodes.isNotEmpty) {
            Logger.info(
              'Fetched ${nodes.length} nodes from external controller API',
            );
            return nodes;
          }
        }
      }
    } catch (e) {
      Logger.debug(
        'External controller API unavailable on :$controllerPort ($e), trying ForkOP cache',
      );
    }

    // 2. Try ForkOP section cache via ubus file.read (/var/run/forkop/section-cache/main.json)
    try {
      final res = await apiService.call(
        routerIp,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': '/var/run/forkop/section-cache/main.json'},
      );

      if (res is List && res.isNotEmpty && res[0] == 0 && res.length > 1) {
        final fileData = res[1] as Map<String, dynamic>?;
        final content = fileData?['data'] as String?;
        if (content != null && content.isNotEmpty) {
          final cacheJson = jsonDecode(content) as Map<String, dynamic>;
          final servers = cacheJson['servers'];
          final outMeta =
              cacheJson['outboundMetadata'] as Map<String, dynamic>? ?? {};
          final nodes = <ForkopNode>[];

          if (servers is Map) {
            servers.forEach((tag, srv) {
              final tagName = tag.toString();
              final meta =
                  outMeta[tagName] is Map ? outMeta[tagName] as Map : null;
              final nodeType = meta?['type']?.toString() ?? 'vless';
              nodes.add(
                ForkopNode(
                  name: tagName,
                  type: ProxyType.fromString(nodeType),
                  server: srv?.toString(),
                ),
              );
            });
          }

          // Add urltest and priority groups as selector groups
          final urltestGroups =
              cacheJson['urltestGroups'] as Map<String, dynamic>?;
          if (urltestGroups != null) {
            urltestGroups.forEach((groupName, _) {
              final label = _knownGroupLabels[groupName];
              nodes.insert(
                0,
                ForkopNode(
                  name: groupName,
                  label: label,
                  type: ProxyType.urltest,
                ),
              );
            });
          }

          final priorityGroups =
              cacheJson['priorityGroups'] as Map<String, dynamic>?;
          if (priorityGroups != null) {
            priorityGroups.forEach((groupName, _) {
              final label = _knownGroupLabels[groupName];
              nodes.insert(
                0,
                ForkopNode(
                  name: groupName,
                  label: label,
                  type: ProxyType.priority,
                ),
              );
            });
          }

          if (nodes.isNotEmpty) {
            Logger.info(
              'Fetched ${nodes.length} nodes from ForkOP section cache',
            );
            return nodes;
          }
        }
      }
    } catch (e) {
      Logger.debug(
        'ForkOP section cache read failed ($e), falling back to ubus scan',
      );
    }

    // 3. Fallback: query router via ubus / shell
    try {
      const script = r'''
if [ -f /etc/mihomo/config.yaml ]; then
  cat /etc/mihomo/config.yaml | grep -E "^\s*-\s*name:" | head -n 30
elif [ -f /etc/sing-box/config.json ]; then
  cat /etc/sing-box/config.json | grep -o '"tag":\s*"[^"]*"' | head -n 30
elif [ -f /etc/config/passwall ]; then
  uci show passwall | grep -E "\.remarks=" | head -n 30
else
  echo "none"
fi
''';
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', script],
      );

      final data = res is List && res.length > 1
          ? res[1] as Map<String, dynamic>?
          : null;
      final stdout = data?['stdout'] as String? ?? '';
      final lines = stdout
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final resultNodes = <ForkopNode>[];
      for (final line in lines) {
        if (line == 'none') break;
        String name = line;
        if (name.contains('name:')) {
          name = name
              .split('name:')
              .last
              .replaceAll("'", '')
              .replaceAll('"', '')
              .trim();
        } else if (name.contains('"tag":')) {
          name = name.replaceAll('"tag":', '').replaceAll('"', '').trim();
        } else if (name.contains('remarks=')) {
          name = name
              .split('remarks=')
              .last
              .replaceAll("'", '')
              .replaceAll('"', '')
              .trim();
        }

        if (name.isNotEmpty) {
          resultNodes.add(
            ForkopNode(name: name, type: ProxyType.fromString(name)),
          );
        }
      }

      return resultNodes;
    } catch (e) {
      Logger.error('Failed to query router nodes via ubus', e);
      return [];
    }
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
        return delay?.toInt();
      }
    } catch (e) {
      Logger.debug('Delay test failed for $nodeName: $e');
    }
    return null;
  }

  /// Selects active node in a selector group (e.g. GLOBAL or PROXY group)
  Future<bool> selectNode({
    required String routerIp,
    required String groupName,
    required String nodeName,
    int controllerPort = 9090,
    String? secret,
  }) async {
    try {
      final url =
          'http://$routerIp:$controllerPort/proxies/${Uri.encodeComponent(groupName)}';
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (secret != null && secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }

      final response = await dio.put<dynamic>(
        url,
        data: jsonEncode({'name': nodeName}),
        options: Options(headers: headers),
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      Logger.error('Failed to select node $nodeName in group $groupName', e);
      return false;
    }
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
      final script =
          '''
curl -k -s -L "$subscriptionUrl" -o "$targetPath.tmp" && mv "$targetPath.tmp" "$targetPath" && /etc/init.d/mihomo restart >/dev/null 2>&1
echo \$?
''';
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/bin/sh',
        params: ['-c', script],
      );
      final data = res is List && res.length > 1
          ? res[1] as Map<String, dynamic>?
          : null;
      final stdout = (data?['stdout'] as String? ?? '').trim();
      return stdout.endsWith('0');
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
        command: '/etc/init.d/forkop',
        params: ['restart'],
      );
      return res is List && res.isNotEmpty && res[0] == 0;
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
        command: '/etc/init.d/forkop',
        params: ['stop'],
      );
      return res is List && res.isNotEmpty && res[0] == 0;
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
        command: '/etc/init.d/forkop',
        params: ['start'],
      );
      return res is List && res.isNotEmpty && res[0] == 0;
    } catch (e) {
      Logger.error('Failed to start forkop', e);
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
      final res = await apiService.systemExec(
        routerIp,
        sysauth,
        useHttps,
        command: '/etc/init.d/forkop',
        params: [enable ? 'enable' : 'disable'],
      );
      return res is List && res.isNotEmpty && res[0] == 0;
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
