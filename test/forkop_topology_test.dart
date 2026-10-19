import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/forkop_node.dart';
import 'package:luci_mobile/services/forkop_service.dart';
import 'package:luci_mobile/services/forkop_topology.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/vpn_topology.json').readAsStringSync())
        as Map<String, dynamic>;
List<ForkopNode> parse(Map f) => ForkopTopology.parse(
  proxies: f['proxies'] as Map,
  config: f['config'] as Map,
  caches: (f['cache'] as List).cast<Map<String, dynamic>>(),
);
void main() {
  test(
    'dynamic groups, exact active chain, real latencies and no infrastructure',
    () {
      final nodes = parse(fixture());
      expect(nodes.where((n) => n.type == ProxyType.urltest).length, 5);
      expect(
        nodes.map((n) => n.displayTitle),
        contains('Авто Hella (Запасной 3)'),
      );
      expect(nodes.where((n) => n.isOnActivePath).map((n) => n.name).toSet(), {
        'main-out',
        'priority-route',
        'auto-shrimp',
        'node-b',
      });
      expect(
        nodes.any(
          (n) =>
              ['direct-out', 'bypass-out', 'GLOBAL', 'REJECT'].contains(n.name),
        ),
        false,
      );
      expect(
        nodes.singleWhere((n) => n.name == 'priority-route').latencyMs,
        167,
      );
      expect(
        nodes.singleWhere((n) => n.name == 'node-b-plus').latencyMs,
        isNull,
      );
      final quick = ForkopTopology.quickChoices(nodes);
      expect(
        quick.map((n) => n.name),
        containsAll(['priority-route', 'auto-shrimp', 'auto-hella', 'node-b']),
      );
      expect(quick.every((n) => n.group.isNotEmpty), true);
      expect(nodes.where((n)=>n.isGroup&&n.isActive).map((n)=>n.name), ['priority-route']);
    },
  );
  test('all concatenated caches parse without splitting strings on braces', () {
    final docs = ForkopTopology.documents(
      '{"name":"quote \\" brace }"}\n{"name":"two"}',
    );
    expect(docs.length, 2);
    expect(ForkopTopology.documents('{broken'), isEmpty);
    expect(ForkopTopology.parse(), isEmpty);
    expect(
      ForkopTopology.parse(
        config: fixture()['config'] as Map,
      ).every((n) => !n.isActive && n.group.isEmpty),
      true,
    );
  });
  test(
    'timeout clears the previous delay instead of keeping a stale value',
    () {
      const node = ForkopNode(name: 'n', type: ProxyType.vless, latencyMs: 123);
      expect(node.copyWith(latencyMs: null).latencyMs, isNull);
      expect(node.copyWith().latencyMs, 123);
      expect(ForkopNode.fromJson({'name': 'n', 'delay': 0}).latencyMs, isNull);
    },
  );
  test('newest timestamp wins regardless of history order and zero is unavailable', () {
    expect(ForkopNode.fromJson({'name':'n','history':[{'time':'2026-10-19T01:00:00Z','delay':7},{'time':'2026-10-18T01:00:00Z','delay':99}]}).latencyMs,7);
    expect(ForkopNode.fromJson({'name':'n','history':[{'time':'2026-10-19T01:00:00Z','delay':0},{'time':'2026-10-18T01:00:00Z','delay':99}]}).latencyMs,isNull);
  });
  test('hundreds of nodes are not truncated and cycles do not invent an active leaf', () {
    final proxies={for(var i=0;i<300;i++) 'node-$i':{'type':'VLESS'}};
    expect(ForkopTopology.parse(proxies:proxies).length,300);
    final f=fixture(); ((f['proxies'] as Map)['priority-route'] as Map)['now']='main-out';
    expect(parse(f).where((n)=>!n.isGroup&&n.isActive),isEmpty);
  });
  for (final apply in [true, false]) {
    test(
      'REST selection requires read-back confirmation (applied=$apply)',
      () async {
        final f = fixture();
        final api = _TopologyApi(f);
        var reads = 0, writes = 0;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                if (o.method == 'GET') {
                  reads++;
                  h.resolve(
                    Response(
                      requestOptions: o,
                      statusCode: 200,
                      data: {'proxies': f['proxies']},
                    ),
                  );
                } else {
                  writes++;
                  if (apply) {
                    ((f['proxies'] as Map)['main-out'] as Map)['now'] =
                        'node-a';
                  }
                  h.resolve(Response(requestOptions: o, statusCode: 204));
                }
              },
            ),
          );
        addTearDown(() => dio.close(force: true));
        final service = ForkopService(apiService: api, dioClient: dio);
        expect(
          await service.selectNode(
            routerIp: 'router',
            sysauth: 'session',
            nodeName: 'node-a',
          ),
          apply,
        );
        expect(reads, greaterThanOrEqualTo(2));
        expect(writes, 1);
        expect(api.switches, isEmpty);
      },
    );
  }
  test(
    'CLI uses the actual parent and raw tag, quotes arguments and confirms state',
    () async {
      final f = fixture();
      const tag = "one' ; reboot";
      (f['proxies'] as Map)[tag] = {'type': 'VLESS'};
      (((f['proxies'] as Map)['main-out'] as Map)['all'] as List).add(tag);
      final api = _TopologyApi(f)..selectedTag = tag;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) => h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              ),
            ),
          ),
        );
      addTearDown(() => dio.close(force: true));
      final service = ForkopService(apiService: api, dioClient: dio);
      expect(
        await service.selectNode(
          routerIp: 'router',
          sysauth: 'session',
          nodeName: tag,
        ),
        true,
      );
      expect(api.switches.single, contains("'main-out' 'one'\\'' ; reboot'"));
      expect(api.switches.single, isNot(contains('uci set')));
      expect(api.switches.single, isNot(contains('|| true')));
      expect(
        await service.selectNode(
          routerIp: 'router',
          sysauth: 'session',
          nodeName: 'direct-out',
        ),
        false,
      );
      expect(
        await service.selectNode(
          routerIp: 'router',
          sysauth: 'session',
          nodeName: 'node-a',
          groupName: 'missing',
        ),
        false,
      );
      expect(api.switches.length, 1);
    },
  );
}

class _TopologyApi implements IApiService {
  final Map<String, dynamic> f;
  String selectedTag = 'node-a';
  final switches = <String>[];
  _TopologyApi(this.f);
  @override
  Future<dynamic> systemExec(
    String ip,
    String token,
    bool https, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    final script = params.last;
    if (script.startsWith('/usr/bin/forkop clash_api set_group_proxy')) {
      switches.add(script);
      ((f['proxies'] as Map)['main-out'] as Map)['now'] = selectedTag;
      return [
        0,
        {'code': 0, 'stdout': ''},
      ];
    }
    if (script.contains('get_proxies')) {
      return [
        0,
        {
          'code': 0,
          'stdout': jsonEncode({'proxies': f['proxies']}),
        },
      ];
    }
    return [
      0,
      {
        'code': 0,
        'stdout':
            '===CACHE===\n${(f['cache'] as List).map(jsonEncode).join('\n')}\n===CONFIG===\n${jsonEncode(f['config'])}',
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
