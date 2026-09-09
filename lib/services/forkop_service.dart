import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:luci_mobile/models/forkop_node.dart';
import 'package:luci_mobile/models/forkop_subscription.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';

class ForkopService {
  final ApiServiceInterface apiService;
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

  /// Attempts to fetch nodes from Mihomo / Clash Meta External Controller REST API
  /// or falls back to querying the router via ubus systemExec.
  Future<List<ForkopNode>> fetchNodes({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    int controllerPort = 9090,
    String? secret,
  }) async {
    // 1. Try Mihomo/Clash external controller API first
    try {
      final protocol = useHttps ? 'https' : 'http';
      final url = '$protocol://$routerIp:$controllerPort/proxies';
      final headers = <String, dynamic>{};
      if (secret != null && secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }

      final response = await dio.get<Map<String, dynamic>>(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final proxiesMap = response.data!['proxies'] as Map<String, dynamic>?;
        if (proxiesMap != null && proxiesMap.isNotEmpty) {
          final nodes = <ForkopNode>[];
          proxiesMap.forEach((name, data) {
            if (data is Map<String, dynamic>) {
              final node = ForkopNode.fromJson({...data, 'name': name});
              nodes.add(node);
            }
          });
          Logger.info('Fetched ${nodes.length} nodes from Mihomo API');
          return nodes;
        }
      }
    } catch (e) {
      Logger.debug(
        'Mihomo external API unavailable ($e), falling back to ubus scan',
      );
    }

    // 2. Fallback: query router via ubus / shell
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
}
