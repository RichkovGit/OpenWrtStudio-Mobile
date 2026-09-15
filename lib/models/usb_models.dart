class UsbDeviceItem {
  final String id;
  final String vendorId;
  final String productId;
  final String name;
  final String deviceType;
  final bool isSupported;

  const UsbDeviceItem({
    required this.id,
    required this.vendorId,
    required this.productId,
    required this.name,
    this.deviceType = 'Устройство',
    this.isSupported = true,
  });
}

class UsbDiskPartition {
  final String deviceNode;
  final String mountPoint;
  final String fileSystem;
  final String label;
  final String totalSize;
  final String usedSize;
  final String freeSize;
  final double usagePercentage;
  final bool isMounted;
  final bool sambaShared;

  const UsbDiskPartition({
    required this.deviceNode,
    this.mountPoint = '',
    this.fileSystem = 'unknown',
    this.label = '',
    this.totalSize = '',
    this.usedSize = '',
    this.freeSize = '',
    this.usagePercentage = 0.0,
    this.isMounted = false,
    this.sambaShared = false,
  });

  UsbDiskPartition copyWith({
    String? deviceNode,
    String? mountPoint,
    String? fileSystem,
    String? label,
    String? totalSize,
    String? usedSize,
    String? freeSize,
    double? usagePercentage,
    bool? isMounted,
    bool? sambaShared,
  }) {
    return UsbDiskPartition(
      deviceNode: deviceNode ?? this.deviceNode,
      mountPoint: mountPoint ?? this.mountPoint,
      fileSystem: fileSystem ?? this.fileSystem,
      label: label ?? this.label,
      totalSize: totalSize ?? this.totalSize,
      usedSize: usedSize ?? this.usedSize,
      freeSize: freeSize ?? this.freeSize,
      usagePercentage: usagePercentage ?? this.usagePercentage,
      isMounted: isMounted ?? this.isMounted,
      sambaShared: sambaShared ?? this.sambaShared,
    );
  }
}

class UsbModemProfile {
  final String interfaceName;
  final String protocol;
  final String deviceNode;
  final String apn;
  final String pinCode;
  final String authType;
  final String username;
  final String password;
  final String pdpType;
  final String status;
  final String signalStrength;
  final String ipAddress;
  final bool isUp;

  const UsbModemProfile({
    this.interfaceName = 'wwan',
    this.protocol = 'qmi',
    this.deviceNode = '/dev/cdc-wdm0',
    this.apn = 'internet',
    this.pinCode = '',
    this.authType = 'none',
    this.username = '',
    this.password = '',
    this.pdpType = 'ipv4',
    this.status = 'Не подключено',
    this.signalStrength = '—',
    this.ipAddress = '—',
    this.isUp = false,
  });

  UsbModemProfile copyWith({
    String? interfaceName,
    String? protocol,
    String? deviceNode,
    String? apn,
    String? pinCode,
    String? authType,
    String? username,
    String? password,
    String? pdpType,
    String? status,
    String? signalStrength,
    String? ipAddress,
    bool? isUp,
  }) {
    return UsbModemProfile(
      interfaceName: interfaceName ?? this.interfaceName,
      protocol: protocol ?? this.protocol,
      deviceNode: deviceNode ?? this.deviceNode,
      apn: apn ?? this.apn,
      pinCode: pinCode ?? this.pinCode,
      authType: authType ?? this.authType,
      username: username ?? this.username,
      password: password ?? this.password,
      pdpType: pdpType ?? this.pdpType,
      status: status ?? this.status,
      signalStrength: signalStrength ?? this.signalStrength,
      ipAddress: ipAddress ?? this.ipAddress,
      isUp: isUp ?? this.isUp,
    );
  }
}

class DiscoveredRouterInfo {
  final String ipAddress;
  final String hostname;
  final String model;
  final String firmware;
  final bool authSucceeded;
  final String statusMessage;

  const DiscoveredRouterInfo({
    required this.ipAddress,
    this.hostname = 'OpenWrt',
    this.model = 'Router',
    this.firmware = '',
    this.authSucceeded = false,
    this.statusMessage = '',
  });

  String get ip => ipAddress;
  bool get isAuthenticated => authSucceeded;
}
