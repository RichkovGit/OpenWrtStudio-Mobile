class DashboardPreferences {
  final Set<String> enabledWirelessInterfaces;
  final Set<String> enabledWiredInterfaces;
  final String? primaryThroughputInterface;
  final bool showAllThroughput;

  DashboardPreferences({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    this.primaryThroughputInterface,
    this.showAllThroughput = true,
  }) : enabledWirelessInterfaces = enabledWirelessInterfaces ?? {},
       enabledWiredInterfaces = enabledWiredInterfaces ?? {};

  DashboardPreferences copyWith({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    String? primaryThroughputInterface,
    bool? showAllThroughput,
  }) {
    return DashboardPreferences(
      enabledWirelessInterfaces:
          enabledWirelessInterfaces ?? this.enabledWirelessInterfaces,
      enabledWiredInterfaces:
          enabledWiredInterfaces ?? this.enabledWiredInterfaces,
      primaryThroughputInterface:
          primaryThroughputInterface ?? this.primaryThroughputInterface,
      showAllThroughput: showAllThroughput ?? this.showAllThroughput,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabledWirelessInterfaces': enabledWirelessInterfaces.toList(),
    'enabledWiredInterfaces': enabledWiredInterfaces.toList(),
    'primaryThroughputInterface': primaryThroughputInterface,
    'showAllThroughput': showAllThroughput,
  };

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    return DashboardPreferences(
      enabledWirelessInterfaces: Set<String>.from(
        json['enabledWirelessInterfaces'] ?? [],
      ),
      enabledWiredInterfaces: Set<String>.from(
        json['enabledWiredInterfaces'] ?? [],
      ),
      primaryThroughputInterface: json['primaryThroughputInterface'],
      showAllThroughput: json['showAllThroughput'] ?? true,
    );
  }

  static DashboardPreferences get defaultPreferences => DashboardPreferences();
}
