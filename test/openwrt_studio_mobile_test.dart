import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/forkop_node.dart';
import 'package:luci_mobile/models/forkop_subscription.dart';
import 'package:luci_mobile/models/protocol_item.dart';
import 'package:luci_mobile/models/sentinel_target.dart';
import 'package:luci_mobile/services/commands_service.dart';

void main() {
  group('ForkOP Node & Subscription Model Tests', () {
    test('ProxyType should parse various strings correctly', () {
      expect(ProxyType.fromString('ss'), ProxyType.shadowsocks);
      expect(ProxyType.fromString('Shadowsocks'), ProxyType.shadowsocks);
      expect(ProxyType.fromString('vmess'), ProxyType.vmess);
      expect(ProxyType.fromString('vless'), ProxyType.vless);
      expect(ProxyType.fromString('trojan'), ProxyType.trojan);
      expect(ProxyType.fromString('hysteria2'), ProxyType.hysteria2);
      expect(ProxyType.fromString('hy2'), ProxyType.hysteria2);
      expect(ProxyType.fromString('wireguard'), ProxyType.wireguard);
      expect(ProxyType.fromString('amneziawg'), ProxyType.amneziawg);
      expect(ProxyType.fromString('selector'), ProxyType.selector);
      expect(ProxyType.fromString('urltest'), ProxyType.urltest);
      expect(ProxyType.fromString('unknown_random'), ProxyType.unknown);
    });

    test('ForkopNode.fromJson parses Mihomo node structure', () {
      final json = {
        'name': 'NL-01-Fast',
        'type': 'vless',
        'server': '198.51.100.10',
        'port': 443,
        'history': [
          {'time': '2026-09-09T12:00:00Z', 'delay': 42},
        ],
        'udp': true,
      };

      final node = ForkopNode.fromJson(json);
      expect(node.name, 'NL-01-Fast');
      expect(node.type, ProxyType.vless);
      expect(node.server, '198.51.100.10');
      expect(node.port, 443);
      expect(node.latencyMs, 42);
      expect(node.isGroup, false);
    });

    test('ForkopNode selector groups identify correctly', () {
      const node = ForkopNode(
        name: 'GLOBAL',
        type: ProxyType.selector,
        now: 'NL-01-Fast',
        all: ['NL-01-Fast', 'US-02', 'DIRECT'],
      );
      expect(node.isGroup, true);
      expect(node.now, 'NL-01-Fast');
      expect(node.all.length, 3);
    });

    test('ForkopSubscription serialization round-trip', () {
      final now = DateTime.now();
      final sub = ForkopSubscription(
        id: 'sub-1',
        name: 'My Service',
        url: 'https://provider.example/sub.yaml',
        updatedAt: now,
        nodeCount: 15,
      );

      final json = sub.toJson();
      final restored = ForkopSubscription.fromJson(json);
      expect(restored.id, 'sub-1');
      expect(restored.name, 'My Service');
      expect(restored.url, 'https://provider.example/sub.yaml');
      expect(restored.nodeCount, 15);
    });
  });

  group('OpenWrt Protocols Model Tests', () {
    test('Default protocol list contains all required OpenWrtStudio protocols', () {
      final protocols = ProtocolItem.defaultList();
      final ids = protocols.map((p) => p.id).toList();

      expect(ids, contains('amneziawg'));
      expect(ids, contains('wireguard'));
      expect(ids, contains('sing-box'));
      expect(ids, contains('mihomo'));
      expect(ids, contains('passwall'));
      expect(ids, contains('openvpn'));
      expect(ids, contains('tailscale'));
      expect(ids, contains('zerotier'));
      expect(ids, contains('xray'));
    });

    test('ProtocolItem status copyWith preserves attributes', () {
      const item = ProtocolItem(
        id: 'mihomo',
        name: 'Mihomo',
        category: ProtocolCategory.proxy,
        description: 'Clash Meta core',
        serviceName: 'mihomo',
        packageNames: ['mihomo'],
        binaryNames: ['mihomo'],
      );

      expect(item.isInstalled, false);
      expect(item.isRunning, false);

      final running = item.copyWith(isInstalled: true, isRunning: true);
      expect(running.isInstalled, true);
      expect(running.isRunning, true);
      expect(running.name, 'Mihomo');
    });
  });

  group('Sentinel Watchdog Model Tests', () {
    test('Default targets include major services', () {
      final targets = SentinelTarget.defaultTargets();
      final names = targets.map((t) => t.name).toList();

      expect(names, contains('Google'));
      expect(names, contains('YouTube'));
      expect(names, contains('Telegram'));
      expect(names, contains('GitHub'));
      expect(names, contains('Cloudflare'));
      expect(names, contains('RuTracker'));
    });

    test('SentinelTarget status and latency updates correctly', () {
      const target = SentinelTarget(
        name: 'Telegram',
        host: 'api.telegram.org',
        category: 'Messengers',
      );

      expect(target.status, SentinelStatus.unknown);

      final checked = target.copyWith(
        status: SentinelStatus.online,
        latencyMs: 38,
      );

      expect(checked.status, SentinelStatus.online);
      expect(checked.latencyMs, 38);
    });
  });

  group('Quick Commands Presets Tests', () {
    test('QuickCommand presets include essential administrative tasks', () {
      final presets = QuickCommand.presets();
      expect(presets.isNotEmpty, true);

      final titles = presets.map((p) => p.title).toList();
      expect(titles.any((t) => t.contains('RAM Cache')), true);
      expect(titles.any((t) => t.contains('DNS')), true);
      expect(titles.any((t) => t.contains('Firewall')), true);
    });
  });
}
