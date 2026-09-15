import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/usb_models.dart';
import 'package:luci_mobile/services/router_discovery_service.dart';

void main() {
  group('USB Models & Discovery Tests', () {
    test('UsbDeviceItem correctly stores hardware identification', () {
      const dev = UsbDeviceItem(
        id: '12d1:1506',
        vendorId: '12d1',
        productId: '1506',
        name: 'Huawei E3372 LTE Modem',
        deviceType: 'Модем',
        isSupported: true,
      );

      expect(dev.id, '12d1:1506');
      expect(dev.vendorId, '12d1');
      expect(dev.productId, '1506');
      expect(dev.name, contains('Huawei'));
      expect(dev.deviceType, 'Модем');
      expect(dev.isSupported, isTrue);
    });

    test(
        'UsbDiskPartition correctly evaluates storage capacity and mount status',
        () {
      const disk = UsbDiskPartition(
        deviceNode: '/dev/sda1',
        mountPoint: '/mnt/sda1',
        fileSystem: 'ext4',
        label: 'USB_BACKUP',
        totalSize: '119.2G',
        usedSize: '14.5G',
        freeSize: '104.7G',
        usagePercentage: 12.0,
        isMounted: true,
        sambaShared: true,
      );

      expect(disk.deviceNode, '/dev/sda1');
      expect(disk.mountPoint, '/mnt/sda1');
      expect(disk.fileSystem, 'ext4');
      expect(disk.label, 'USB_BACKUP');
      expect(disk.isMounted, isTrue);
      expect(disk.sambaShared, isTrue);
      expect(disk.usagePercentage, 12.0);
    });

    test('UsbModemProfile copyWith works as expected', () {
      const profile = UsbModemProfile();
      expect(profile.protocol, 'qmi');
      expect(profile.deviceNode, '/dev/cdc-wdm0');
      expect(profile.apn, 'internet');
      expect(profile.isUp, isFalse);

      final updated = profile.copyWith(
        protocol: 'mbim',
        apn: 'internet.tele2.ru',
        isUp: true,
        signalStrength: '-65 dBm (Good)',
      );

      expect(updated.protocol, 'mbim');
      expect(updated.apn, 'internet.tele2.ru');
      expect(updated.isUp, isTrue);
      expect(updated.signalStrength, contains('-65 dBm'));
      expect(updated.deviceNode, '/dev/cdc-wdm0');
    });

    test('DiscoveredRouterInfo convenience getters operate properly', () {
      const info = DiscoveredRouterInfo(
        ipAddress: '192.168.10.1',
        hostname: 'OpenWrt-Filogic',
        model: 'Cudy WR3000S',
        firmware: 'OpenWrt 25.12.5',
        authSucceeded: true,
        statusMessage: 'OK',
      );

      expect(info.ip, '192.168.10.1');
      expect(info.isAuthenticated, isTrue);
      expect(info.hostname, 'OpenWrt-Filogic');
      expect(info.model, 'Cudy WR3000S');
    });

    test('RouterDiscoveryService provides default candidates', () {
      final discovery = RouterDiscoveryService();
      expect(discovery.defaultCandidates, contains('192.168.1.1'));
      expect(discovery.defaultCandidates, contains('192.168.10.1'));
      expect(discovery.defaultCandidates, contains('192.168.0.1'));
      expect(discovery.defaultCandidates, contains('192.168.8.1'));
    });
  });
}
