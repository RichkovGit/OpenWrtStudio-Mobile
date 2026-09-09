enum SentinelStatus {
  online,
  blocked,
  timeout,
  pending,
  unknown;

  String get displayName => switch (this) {
    SentinelStatus.online => 'Online',
    SentinelStatus.blocked => 'Blocked',
    SentinelStatus.timeout => 'Timeout',
    SentinelStatus.pending => 'Checking...',
    SentinelStatus.unknown => 'Unknown',
  };
}

class SentinelTarget {
  final String name;
  final String host;
  final String category;
  final SentinelStatus status;
  final int? latencyMs;
  final DateTime? lastChecked;
  final String? details;

  const SentinelTarget({
    required this.name,
    required this.host,
    required this.category,
    this.status = SentinelStatus.unknown,
    this.latencyMs,
    this.lastChecked,
    this.details,
  });

  SentinelTarget copyWith({
    String? name,
    String? host,
    String? category,
    SentinelStatus? status,
    int? latencyMs,
    DateTime? lastChecked,
    String? details,
  }) {
    return SentinelTarget(
      name: name ?? this.name,
      host: host ?? this.host,
      category: category ?? this.category,
      status: status ?? this.status,
      latencyMs: latencyMs ?? this.latencyMs,
      lastChecked: lastChecked ?? this.lastChecked,
      details: details ?? this.details,
    );
  }

  factory SentinelTarget.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    final status = switch (statusStr) {
      'online' => SentinelStatus.online,
      'blocked' => SentinelStatus.blocked,
      'timeout' => SentinelStatus.timeout,
      'pending' => SentinelStatus.pending,
      _ => SentinelStatus.unknown,
    };

    return SentinelTarget(
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      status: status,
      latencyMs: json['latencyMs'] as int?,
      lastChecked: json['lastChecked'] != null
          ? DateTime.tryParse(json['lastChecked'] as String)
          : null,
      details: json['details'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'host': host,
    'category': category,
    'status': status.name,
    'latencyMs': latencyMs,
    'lastChecked': lastChecked?.toIso8601String(),
    'details': details,
  };

  static List<SentinelTarget> defaultTargets() => [
    const SentinelTarget(
      name: 'Google',
      host: 'www.google.com',
      category: 'Search & Infrastructure',
    ),
    const SentinelTarget(
      name: 'YouTube',
      host: 'www.youtube.com',
      category: 'Media & Streaming',
    ),
    const SentinelTarget(
      name: 'Telegram',
      host: 'api.telegram.org',
      category: 'Messengers',
    ),
    const SentinelTarget(
      name: 'GitHub',
      host: 'github.com',
      category: 'Developer Services',
    ),
    const SentinelTarget(
      name: 'Cloudflare',
      host: '1.1.1.1',
      category: 'DNS & CDN',
    ),
    const SentinelTarget(
      name: 'RuTracker',
      host: 'rutracker.org',
      category: 'Bypass Verification',
    ),
  ];
}
