class ForkopSubscription {
  final String id;
  final String name;
  final String url;
  final DateTime? updatedAt;
  final int nodeCount;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final DateTime? expireDate;

  const ForkopSubscription({
    required this.id,
    required this.name,
    required this.url,
    this.updatedAt,
    this.nodeCount = 0,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expireDate,
  });

  ForkopSubscription copyWith({
    String? id,
    String? name,
    String? url,
    DateTime? updatedAt,
    int? nodeCount,
    int? uploadBytes,
    int? downloadBytes,
    int? totalBytes,
    DateTime? expireDate,
  }) {
    return ForkopSubscription(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      updatedAt: updatedAt ?? this.updatedAt,
      nodeCount: nodeCount ?? this.nodeCount,
      uploadBytes: uploadBytes ?? this.uploadBytes,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      expireDate: expireDate ?? this.expireDate,
    );
  }

  factory ForkopSubscription.fromJson(Map<String, dynamic> json) {
    return ForkopSubscription(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Subscription',
      url: json['url'] as String? ?? '',
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      nodeCount: json['nodeCount'] as int? ?? 0,
      uploadBytes: json['uploadBytes'] as int?,
      downloadBytes: json['downloadBytes'] as int?,
      totalBytes: json['totalBytes'] as int?,
      expireDate: json['expireDate'] != null
          ? DateTime.tryParse(json['expireDate'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'updatedAt': updatedAt?.toIso8601String(),
    'nodeCount': nodeCount,
    'uploadBytes': uploadBytes,
    'downloadBytes': downloadBytes,
    'totalBytes': totalBytes,
    'expireDate': expireDate?.toIso8601String(),
  };
}
