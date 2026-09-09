enum ProtocolCategory {
  vpn,
  proxy,
  mesh,
  other;

  String get displayName => switch (this) {
    ProtocolCategory.vpn => 'VPN',
    ProtocolCategory.proxy => 'Proxy / Bypass',
    ProtocolCategory.mesh => 'Mesh VPN',
    ProtocolCategory.other => 'Other',
  };
}

class ProtocolItem {
  final String id;
  final String name;
  final ProtocolCategory category;
  final String description;
  final bool isInstalled;
  final bool isRunning;
  final bool isEnabled;
  final String serviceName;
  final List<String> packageNames;
  final List<String> binaryNames;
  final String? configName;
  final String? version;

  const ProtocolItem({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.isInstalled = false,
    this.isRunning = false,
    this.isEnabled = false,
    required this.serviceName,
    required this.packageNames,
    required this.binaryNames,
    this.configName,
    this.version,
  });

  ProtocolItem copyWith({
    String? id,
    String? name,
    ProtocolCategory? category,
    String? description,
    bool? isInstalled,
    bool? isRunning,
    bool? isEnabled,
    String? serviceName,
    List<String>? packageNames,
    List<String>? binaryNames,
    String? configName,
    String? version,
  }) {
    return ProtocolItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      isInstalled: isInstalled ?? this.isInstalled,
      isRunning: isRunning ?? this.isRunning,
      isEnabled: isEnabled ?? this.isEnabled,
      serviceName: serviceName ?? this.serviceName,
      packageNames: packageNames ?? this.packageNames,
      binaryNames: binaryNames ?? this.binaryNames,
      configName: configName ?? this.configName,
      version: version ?? this.version,
    );
  }

  factory ProtocolItem.fromJson(Map<String, dynamic> json) {
    final catStr = (json['category'] as String?)?.toLowerCase();
    final category = switch (catStr) {
      'vpn' => ProtocolCategory.vpn,
      'proxy' => ProtocolCategory.proxy,
      'mesh' => ProtocolCategory.mesh,
      _ => ProtocolCategory.other,
    };

    return ProtocolItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: category,
      description: json['description'] as String? ?? '',
      isInstalled: json['isInstalled'] as bool? ?? false,
      isRunning: json['isRunning'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? false,
      serviceName: json['serviceName'] as String? ?? '',
      packageNames: (json['packageNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      binaryNames: (json['binaryNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      configName: json['configName'] as String?,
      version: json['version'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'description': description,
    'isInstalled': isInstalled,
    'isRunning': isRunning,
    'isEnabled': isEnabled,
    'serviceName': serviceName,
    'packageNames': packageNames,
    'binaryNames': binaryNames,
    'configName': configName,
    'version': version,
  };

  static List<ProtocolItem> defaultList() => [
    const ProtocolItem(
      id: 'amneziawg',
      name: 'AmneziaWG',
      category: ProtocolCategory.vpn,
      description: 'Modern obfuscated WireGuard fork designed to bypass deep packet inspection (DPI).',
      serviceName: 'amneziawg',
      packageNames: ['kmod-amneziawg', 'amneziawg-tools', 'luci-app-amneziawg'],
      binaryNames: ['awg', 'awg-quick'],
      configName: 'amneziawg',
    ),
    const ProtocolItem(
      id: 'wireguard',
      name: 'WireGuard',
      category: ProtocolCategory.vpn,
      description: 'Extremely fast, modern, and secure VPN kernel-level tunnel.',
      serviceName: 'wireguard',
      packageNames: ['kmod-wireguard', 'wireguard-tools', 'luci-proto-wireguard'],
      binaryNames: ['wg', 'wg-quick'],
      configName: 'network',
    ),
    const ProtocolItem(
      id: 'sing-box',
      name: 'Sing-box',
      category: ProtocolCategory.proxy,
      description: 'Universal proxy platform with superior performance, TUN routing, and modern protocols.',
      serviceName: 'sing-box',
      packageNames: ['sing-box'],
      binaryNames: ['sing-box'],
      configName: 'sing-box',
    ),
    const ProtocolItem(
      id: 'mihomo',
      name: 'Mihomo (Clash Meta)',
      category: ProtocolCategory.proxy,
      description: 'Feature-rich rule-based proxy client supporting Clash Meta configs and Subscriptions.',
      serviceName: 'mihomo',
      packageNames: ['mihomo', 'luci-app-mihomo', 'nikki', 'openclash'],
      binaryNames: ['mihomo', 'clash'],
      configName: 'mihomo',
    ),
    const ProtocolItem(
      id: 'passwall',
      name: 'PassWall 2',
      category: ProtocolCategory.proxy,
      description: 'Comprehensive OpenWrt bypass and multi-protocol proxy director.',
      serviceName: 'passwall',
      packageNames: ['passwall', 'luci-app-passwall', 'luci-app-passwall2'],
      binaryNames: ['passwall'],
      configName: 'passwall',
    ),
    const ProtocolItem(
      id: 'openvpn',
      name: 'OpenVPN',
      category: ProtocolCategory.vpn,
      description: 'Battle-tested, reliable open source SSL/TLS VPN solution.',
      serviceName: 'openvpn',
      packageNames: ['openvpn-openssl', 'openvpn-mbedtls', 'luci-app-openvpn'],
      binaryNames: ['openvpn'],
      configName: 'openvpn',
    ),
    const ProtocolItem(
      id: 'tailscale',
      name: 'Tailscale',
      category: ProtocolCategory.mesh,
      description: 'Zero-config WireGuard mesh network connecting devices anywhere securely.',
      serviceName: 'tailscale',
      packageNames: ['tailscale', 'luci-app-tailscale'],
      binaryNames: ['tailscale', 'tailscaled'],
      configName: 'tailscale',
    ),
    const ProtocolItem(
      id: 'zerotier',
      name: 'ZeroTier',
      category: ProtocolCategory.mesh,
      description: 'Decentralized software-defined virtual Ethernet switch for mesh connectivity.',
      serviceName: 'zerotier',
      packageNames: ['zerotier', 'luci-app-zerotier'],
      binaryNames: ['zerotier-one', 'zerotier-cli'],
      configName: 'zerotier',
    ),
    const ProtocolItem(
      id: 'xray',
      name: 'Xray-core',
      category: ProtocolCategory.proxy,
      description: 'High-performance core for VLESS, VMess, XTLS, Trojan, and reality routing.',
      serviceName: 'xray',
      packageNames: ['xray-core', 'xray'],
      binaryNames: ['xray'],
      configName: 'xray',
    ),
  ];
}
