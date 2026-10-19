const _unsetDelay = Object();

enum ProxyType {
  shadowsocks,
  vmess,
  vless,
  trojan,
  hysteria,
  hysteria2,
  tuic,
  wireguard,
  amneziawg,
  direct,
  reject,
  selector,
  urltest,
  priority,
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
      'tuic' => ProxyType.tuic,
      'wireguard' || 'wg' => ProxyType.wireguard,
      'amneziawg' || 'awg' => ProxyType.amneziawg,
      'direct' => ProxyType.direct,
      'reject' => ProxyType.reject,
      'selector' => ProxyType.selector,
      'urltest' => ProxyType.urltest,
      'priority' => ProxyType.priority,
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
    ProxyType.tuic => 'TUIC',
    ProxyType.wireguard => 'WireGuard',
    ProxyType.amneziawg => 'AmneziaWG',
    ProxyType.direct => 'Direct',
    ProxyType.reject => 'Reject',
    ProxyType.selector => 'Selector',
    ProxyType.urltest => 'URLTest',
    ProxyType.priority => 'Priority',
    ProxyType.fallback => 'Fallback',
    ProxyType.unknown => 'Other',
  };
}

class ForkopNode {
  final String name;
  final String? label;
  final ProxyType type;
  final String? server;
  final int? port;
  final int? latencyMs;
  final bool isActive;
  final String group;
  final bool udp;
  final bool hasLiveState;
  final bool isOnActivePath;
  final bool canSelectMembers;
  final String? now; // Selected node if this is a selector group
  final List<String> all; // Candidate node names for groups

  const ForkopNode({
    required this.name,
    this.label,
    required this.type,
    this.server,
    this.port,
    this.latencyMs,
    this.isActive = false,
    this.group = '',
    this.hasLiveState = false,
    this.isOnActivePath = false,
    this.canSelectMembers = false,
    this.udp = true,
    this.now,
    this.all = const [],
  });

  String get displayTitle =>
      (label != null && label!.isNotEmpty) ? label! : name;

  bool get isGroup =>
      type == ProxyType.selector ||
      type == ProxyType.urltest ||
      type == ProxyType.priority ||
      type == ProxyType.fallback ||
      all.isNotEmpty;

  ForkopNode copyWith({
    String? name,
    String? label,
    ProxyType? type,
    String? server,
    int? port,
    Object? latencyMs = _unsetDelay,
    bool? isActive,
    String? group,
    bool? udp,
    String? now,
    List<String>? all,
  }) {
    return ForkopNode(
      name: name ?? this.name,
      label: label ?? this.label,
      type: type ?? this.type,
      server: server ?? this.server,
      port: port ?? this.port,
      latencyMs: identical(latencyMs, _unsetDelay)
          ? this.latencyMs
          : latencyMs as int?,
      isActive: isActive ?? this.isActive,
      group: group ?? this.group,
      hasLiveState: hasLiveState,
      isOnActivePath: isOnActivePath,
      canSelectMembers: canSelectMembers,
      udp: udp ?? this.udp,
      now: now ?? this.now,
      all: all ?? this.all,
    );
  }

  static int? latestDelay(dynamic history, dynamic fallback) {
    dynamic value = fallback;
    if (history is List && history.isNotEmpty) {
      dynamic latest = history.last;
      DateTime? newest;
      for (final entry in history) {
        if (entry is! Map) continue;
        final time = DateTime.tryParse(entry['time']?.toString() ?? '');
        if (time != null && (newest == null || !time.isBefore(newest))) {
          newest = time;
          latest = entry;
        }
      }
      value = latest is Map ? latest['delay'] : null;
    }
    return value is num && value > 0 ? value.toInt() : null;
  }

  factory ForkopNode.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    final delay = latestDelay(json['history'], json['delay']);

    final allList =
        (json['all'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        [];

    return ForkopNode(
      name: json['name'] as String? ?? 'Unnamed',
      label: json['label'] as String?,
      type: ProxyType.fromString(rawType),
      server: json['server'] as String?,
      port: json['port'] is num ? (json['port'] as num).toInt() : null,
      latencyMs: delay != null && delay > 0 ? delay : null,
      isActive: json['isActive'] as bool? ?? false,
      group: json['group'] as String? ?? '',
      hasLiveState: json['hasLiveState'] as bool? ?? false,
      isOnActivePath: json['isOnActivePath'] as bool? ?? false,
      canSelectMembers: json['canSelectMembers'] as bool? ?? false,
      udp: json['udp'] as bool? ?? true,
      now: json['now'] is String ? json['now'] as String : null,
      all: allList,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'label': label,
    'hasLiveState': hasLiveState,
    'canSelectMembers': canSelectMembers,
    'isOnActivePath': isOnActivePath,
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
