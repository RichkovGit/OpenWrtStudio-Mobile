enum ProxyType {
  shadowsocks,
  vmess,
  vless,
  trojan,
  hysteria,
  hysteria2,
  wireguard,
  amneziawg,
  direct,
  reject,
  selector,
  urltest,
  fallback,
  unknown;

  static ProxyType fromString(String? type) {
    if (type == null) return ProxyType.unknown;
    final lower = type.toLowerCase();
    return switch (lower) {
      'shadowsocks' || 'ss' => ProxyType.shadowsocks,
      'vmess' => ProxyType.vmess,
      'vless' => ProxyType.vless,
      'trojan' => ProxyType.trojan,
      'hysteria' => ProxyType.hysteria,
      'hysteria2' || 'hy2' => ProxyType.hysteria2,
      'wireguard' || 'wg' => ProxyType.wireguard,
      'amneziawg' || 'awg' => ProxyType.amneziawg,
      'direct' => ProxyType.direct,
      'reject' => ProxyType.reject,
      'selector' => ProxyType.selector,
      'urltest' => ProxyType.urltest,
      'fallback' => ProxyType.fallback,
      _ => ProxyType.unknown,
    };
  }

  String get displayName => switch (this) {
    ProxyType.shadowsocks => 'Shadowsocks',
    ProxyType.vmess => 'VMess',
    ProxyType.vless => 'VLESS',
    ProxyType.trojan => 'Trojan',
    ProxyType.hysteria => 'Hysteria',
    ProxyType.hysteria2 => 'Hysteria 2',
    ProxyType.wireguard => 'WireGuard',
    ProxyType.amneziawg => 'AmneziaWG',
    ProxyType.direct => 'Direct',
    ProxyType.reject => 'Reject',
    ProxyType.selector => 'Selector',
    ProxyType.urltest => 'Auto (URL-Test)',
    ProxyType.fallback => 'Fallback',
    ProxyType.unknown => 'Other',
  };
}

class ForkopNode {
  final String name;
  final ProxyType type;
  final String? server;
  final int? port;
  final int? latencyMs;
  final bool isActive;
  final String group;
  final bool udp;
  final String? now; // Selected node if this is a selector group
  final List<String> all; // Candidate node names for groups

  const ForkopNode({
    required this.name,
    required this.type,
    this.server,
    this.port,
    this.latencyMs,
    this.isActive = false,
    this.group = 'PROXY',
    this.udp = true,
    this.now,
    this.all = const [],
  });

  bool get isGroup =>
      type == ProxyType.selector ||
      type == ProxyType.urltest ||
      type == ProxyType.fallback;

  ForkopNode copyWith({
    String? name,
    ProxyType? type,
    String? server,
    int? port,
    int? latencyMs,
    bool? isActive,
    String? group,
    bool? udp,
    String? now,
    List<String>? all,
  }) {
    return ForkopNode(
      name: name ?? this.name,
      type: type ?? this.type,
      server: server ?? this.server,
      port: port ?? this.port,
      latencyMs: latencyMs ?? this.latencyMs,
      isActive: isActive ?? this.isActive,
      group: group ?? this.group,
      udp: udp ?? this.udp,
      now: now ?? this.now,
      all: all ?? this.all,
    );
  }

  factory ForkopNode.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String?;
    final history = json['history'] as List<dynamic>?;
    int? delay;
    if (history != null && history.isNotEmpty) {
      final last = history.last as Map<String, dynamic>?;
      if (last != null && last['delay'] is num) {
        delay = (last['delay'] as num).toInt();
      }
    } else if (json['delay'] is num) {
      delay = (json['delay'] as num).toInt();
    }

    final allList = (json['all'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return ForkopNode(
      name: json['name'] as String? ?? 'Unnamed',
      type: ProxyType.fromString(rawType),
      server: json['server'] as String?,
      port: json['port'] as int?,
      latencyMs: delay,
      isActive: json['isActive'] as bool? ?? false,
      group: json['group'] as String? ?? 'PROXY',
      udp: json['udp'] as bool? ?? true,
      now: json['now'] as String?,
      all: allList,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'server': server,
    'port': port,
    'latencyMs': latencyMs,
    'isActive': isActive,
    'group': group,
    'udp': udp,
    'now': now,
    'all': all,
  };
}
