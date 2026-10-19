import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/forkop_node.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/forkop_service.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';

void main() {
  final host = Platform.environment['OPENWRT_TEST_HOST'];
  final password = Platform.environment['OPENWRT_TEST_PASSWORD'];
  final enabled =
      Platform.environment['OPENWRT_LIVE_VALIDATION'] == '1' &&
      host != null &&
      password != null;
  test(
    'live topology and rejected command never report a successful switch',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() async {
        HttpOverrides.global = previousOverrides;
        await HttpClientManager().clearAcceptedCertificates();
      });
      final api = RealApiService();
      final token = await api.login(host!, 'root', password!, false);
      Future<Map<String, dynamic>> readProxies() async {
        final result = await api.systemExec(
          host,
          token,
          false,
          command: '/bin/sh',
          params: ['-c', '/usr/bin/forkop clash_api get_proxies'],
        );
        expect(result[0], 0);
        expect(result[1]['code'], 0);
        return (jsonDecode(result[1]['stdout'] as String)
                as Map<String, dynamic>)['proxies']
            as Map<String, dynamic>;
      }

      Map<String, String> selectors(Map<String, dynamic> proxies) => {
        for (final e in proxies.entries)
          if (e.value['type'] == 'Selector') e.key: e.value['now'] as String,
      };
      final before = await readProxies();
      final service = ForkopService(apiService: api);
      addTearDown(() => service.dio.close(force: true));
      final nodes = await service.fetchNodes(
        routerIp: host,
        sysauth: token,
        useHttps: false,
      );
      expect(nodes.where((n) => !n.isGroup), isNotEmpty);
      expect(nodes.where((n) => n.type == ProxyType.urltest), isNotEmpty);
      expect(nodes.where((n) => n.isActive && !n.isGroup), hasLength(1));
      for (final node in nodes.where((n) => n.hasLiveState && n.isGroup)) {
        expect(
          node.now,
          before[node.name]['now'],
          reason: 'Live selected member',
        );
      }
      expect(
        await service.selectNode(
          routerIp: host,
          sysauth: token,
          nodeName: '__studio_missing_target__',
        ),
        isFalse,
      );
      expect(selectors(await readProxies()), selectors(before));

      // Keep GETs real. Simulate only an unavailable controller write so the
      // normal CLI fallback reaches the real router with an invalid RPC session.
      // This denies file.exec without altering accounts, ACLs or router services.
      var deniedWrites = 0;
      final deniedDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'PUT') {
                deniedWrites++;
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                  ),
                );
              } else {
                handler.next(options);
              }
            },
          ),
        );
      addTearDown(() => deniedDio.close(force: true));
      final denied = ForkopService(apiService: api, dioClient: deniedDio);
      final target = nodes.firstWhere(
        (n) => !n.isGroup && n.group == 'main-out' && !n.isActive,
      );
      expect(
        await denied.selectNode(
          routerIp: host,
          sysauth: 'invalid-studio-qa-session',
          nodeName: target.name,
          groupName: 'main-out',
        ),
        isFalse,
      );
      expect(deniedWrites, 1);
      expect(selectors(await readProxies()), selectors(before));
    },
    skip: enabled
        ? false
        : 'Opt in with OPENWRT_LIVE_VALIDATION=1 and local router credentials.',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
