import 'package:luci_mobile/models/usb_models.dart';
import 'package:luci_mobile/services/commands_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';

class UsbConfigService {
  final IApiService apiService;
  late final CommandsService commandsService;

  UsbConfigService({required this.apiService}) {
    commandsService = CommandsService(apiService: apiService);
  }

  Future<List<UsbDeviceItem>> getUsbDevices({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    final list = <UsbDeviceItem>[];

    // Try lsusb
    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: 'lsusb 2>/dev/null',
    );

    if (res.isSuccess && res.stdout.trim().isNotEmpty) {
      final lines = res.stdout.split('\n');
      for (final line in lines) {
        final reg = RegExp(
            r'Bus\s+(\d+)\s+Device\s+(\d+):\s+ID\s+([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\s*(.*)');
        final match = reg.firstMatch(line);
        if (match != null) {
          final vid = match.group(3)!;
          final pid = match.group(4)!;
          final desc = match.group(5)!.trim();
          var type = 'USB Устройство';
          if (desc.toLowerCase().contains('modem') ||
              desc.toLowerCase().contains('huawei') ||
              desc.toLowerCase().contains('zte') ||
              desc.toLowerCase().contains('lte')) {
            type = 'Модем';
          } else if (desc.toLowerCase().contains('storage') ||
              desc.toLowerCase().contains('flash') ||
              desc.toLowerCase().contains('disk')) {
            type = 'Накопитель';
          }

          list.add(UsbDeviceItem(
            id: '$vid:$pid',
            vendorId: vid,
            productId: pid,
            name: desc.isNotEmpty ? desc : 'USB Device ($vid:$pid)',
            deviceType: type,
          ));
        }
      }
    }

    // Fallback: /sys/bus/usb/devices/
    if (list.isEmpty) {
      final sysRes = await commandsService.execute(
        routerIp: routerIp,
        sysauth: sysauth,
        useHttps: useHttps,
        command:
            'for d in /sys/bus/usb/devices/*; do [ -f "\$d/idVendor" ] && echo "\$(cat \$d/idVendor):\$(cat \$d/idProduct)|\$(cat \$d/manufacturer 2>/dev/null)|\$(cat \$d/product 2>/dev/null)"; done',
      );
      if (sysRes.isSuccess && sysRes.stdout.trim().isNotEmpty) {
        final lines = sysRes.stdout.split('\n');
        for (final line in lines) {
          final parts = line.trim().split('|');
          if (parts.isNotEmpty && parts[0].contains(':')) {
            final ids = parts[0].split(':');
            final vid = ids[0];
            final pid = ids.length > 1 ? ids[1] : '';
            final man = parts.length > 1 ? parts[1].trim() : '';
            final prod = parts.length > 2 ? parts[2].trim() : '';
            final name = '$man $prod'.trim();

            var type = 'USB Устройство';
            if (name.toLowerCase().contains('modem') ||
                name.toLowerCase().contains('lte')) {
              type = 'Модем';
            } else if (name.toLowerCase().contains('storage') ||
                name.toLowerCase().contains('flash')) {
              type = 'Накопитель';
            }

            list.add(UsbDeviceItem(
              id: '$vid:$pid',
              vendorId: vid,
              productId: pid,
              name: name.isNotEmpty ? name : 'USB Device ($vid:$pid)',
              deviceType: type,
            ));
          }
        }
      }
    }

    return list;
  }

  Future<List<UsbDiskPartition>> getStorageDisks({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    final partitions = <String, UsbDiskPartition>{};

    // 1. block info / blkid
    final bRes = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: 'block info 2>/dev/null || blkid 2>/dev/null',
    );

    if (bRes.isSuccess && bRes.stdout.trim().isNotEmpty) {
      final lines = bRes.stdout.split('\n');
      for (final line in lines) {
        final devMatch = RegExp(r'^(/dev/sd[a-z][0-9]*):').firstMatch(line);
        if (devMatch != null) {
          final devNode = devMatch.group(1)!;
          final fsMatch = RegExp(r'TYPE="([^"]+)"').firstMatch(line);
          final labelMatch = RegExp(r'LABEL="([^"]+)"').firstMatch(line);

          partitions[devNode] = UsbDiskPartition(
            deviceNode: devNode,
            fileSystem: fsMatch != null ? fsMatch.group(1)! : 'unknown',
            label: labelMatch != null ? labelMatch.group(1)! : '',
          );
        }
      }
    }

    // 2. df -h
    final dfRes = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: 'df -h',
    );

    if (dfRes.isSuccess && dfRes.stdout.trim().isNotEmpty) {
      final lines = dfRes.stdout.split('\n');
      for (final line in lines) {
        final m = RegExp(
                r'^(/dev/sd[a-z][0-9]*)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)%\s+(.+)')
            .firstMatch(line);
        if (m != null) {
          final dev = m.group(1)!;
          final total = m.group(2)!;
          final used = m.group(3)!;
          final free = m.group(4)!;
          final pct = double.tryParse(m.group(5)!) ?? 0.0;
          final mnt = m.group(6)!.trim();

          final existing = partitions[dev];
          partitions[dev] =
              (existing ?? UsbDiskPartition(deviceNode: dev)).copyWith(
            totalSize: total,
            usedSize: used,
            freeSize: free,
            usagePercentage: pct,
            mountPoint: mnt,
            isMounted: true,
          );
        }
      }
    }

    return partitions.values.toList();
  }

  Future<UsbModemProfile> getModemProfile({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    var profile = const UsbModemProfile();

    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: 'uci show network.wwan 2>/dev/null',
    );

    if (res.isSuccess && res.stdout.trim().isNotEmpty) {
      final lines = res.stdout.split('\n');
      for (final line in lines) {
        final kv = line.trim().split('=');
        if (kv.length == 2) {
          final key = kv[0].replaceAll('network.wwan.', '').trim();
          final val = kv[1].replaceAll("'", '').replaceAll('"', '').trim();

          switch (key) {
            case 'proto':
              profile = profile.copyWith(protocol: val);
              break;
            case 'device':
              profile = profile.copyWith(deviceNode: val);
              break;
            case 'apn':
              profile = profile.copyWith(apn: val);
              break;
            case 'pincode':
              profile = profile.copyWith(pinCode: val);
              break;
            case 'auth':
              profile = profile.copyWith(authType: val);
              break;
            case 'username':
              profile = profile.copyWith(username: val);
              break;
            case 'password':
              profile = profile.copyWith(password: val);
              break;
            case 'pdptype':
              profile = profile.copyWith(pdpType: val);
              break;
          }
        }
      }
    }

    // Check status via ubus
    final uRes = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: 'ubus call network.interface.wwan status 2>/dev/null',
    );

    if (uRes.isSuccess && uRes.stdout.trim().isNotEmpty) {
      final isUp = uRes.stdout.contains('"up": true');
      final ipMatch = RegExp(r'"address":\s*"([^"]+)"').firstMatch(uRes.stdout);
      profile = profile.copyWith(
        isUp: isUp,
        status: isUp ? 'Подключено (Онлайн)' : 'Интерфейс остановлен',
        ipAddress: ipMatch != null ? ipMatch.group(1)! : '—',
      );
    } else {
      profile = profile.copyWith(status: 'Интерфейс не настроен в системе');
    }

    return profile;
  }

  Future<bool> saveModemProfile({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required UsbModemProfile profile,
  }) async {
    final cmd = 'uci set network.${profile.interfaceName}=interface && '
        "uci set network.${profile.interfaceName}.proto='${profile.protocol}' && "
        "uci set network.${profile.interfaceName}.device='${profile.deviceNode}' && "
        "uci set network.${profile.interfaceName}.apn='${profile.apn}' && "
        "uci set network.${profile.interfaceName}.pdptype='${profile.pdpType}' && "
        "uci set network.${profile.interfaceName}.auth='${profile.authType}' && "
        'uci commit network';

    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: cmd,
    );
    return res.isSuccess;
  }

  Future<bool> restartModemInterface({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    String interfaceName = 'wwan',
  }) async {
    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command:
          'ifdown $interfaceName 2>/dev/null; sleep 1; ifup $interfaceName 2>/dev/null || /etc/init.d/network reload',
    );
    return res.isSuccess;
  }

  Future<bool> mountDisk({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String deviceNode,
    required String mountPoint,
    String? fileSystem,
  }) async {
    final fs = (fileSystem ?? '').toLowerCase();
    String mountCmd;

    if (fs.contains('exfat')) {
      // exFAT support with UTF-8 and full permissions
      mountCmd =
          'mount -t exfat -o rw,noatime,iocharset=utf8,umask=000,dmask=0000,fmask=0000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount -o rw,noatime,iocharset=utf8,umask=000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount "$deviceNode" "$mountPoint"';
    } else if (fs.contains('vfat') || fs.contains('fat')) {
      // Windows FAT32 with Russian/Cyrillic support (CP866 + UTF-8) and full read/write permissions
      mountCmd =
          'mount -t vfat -o rw,noatime,iocharset=utf8,utf8=1,codepage=866,umask=000,dmask=0000,fmask=0000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount -o rw,noatime,iocharset=utf8,utf8=1,umask=000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount "$deviceNode" "$mountPoint"';
    } else if (fs.contains('ntfs')) {
      // Windows NTFS with ntfs-3g or kernel ntfs3 driver, UTF-8 and full write permissions
      mountCmd =
          'ntfs-3g -o rw,noatime,big_writes,iocharset=utf8,umask=000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount -t ntfs3 -o rw,noatime,iocharset=utf8,umask=000,dmask=0000,fmask=0000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount -o rw,noatime,iocharset=utf8,umask=000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount "$deviceNode" "$mountPoint"';
    } else {
      mountCmd =
          'mount -o rw,noatime,iocharset=utf8,utf8=1,umask=000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount -o rw,noatime,umask=000 "$deviceNode" "$mountPoint" 2>/dev/null || '
          'mount "$deviceNode" "$mountPoint"';
    }

    final cmd =
        'mkdir -p "$mountPoint" && ($mountCmd) && (chmod 777 "$mountPoint" 2>/dev/null || true) && '
        'block detect > /etc/config/fstab 2>/dev/null && '
        "uci set fstab.@mount[-1].options='rw,sync,noatime,iocharset=utf8,utf8=1,codepage=866,umask=000' 2>/dev/null && "
        'uci commit fstab 2>/dev/null';

    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: cmd,
    );

    if (res.isSuccess) {
      // Set up hotplug automounting script in background
      ensureHotplugAutomountScript(
        routerIp: routerIp,
        sysauth: sysauth,
        useHttps: useHttps,
      );
    }

    return res.isSuccess;
  }

  Future<bool> unmountDisk({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String mountPoint,
  }) async {
    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: 'umount "$mountPoint"',
    );
    return res.isSuccess;
  }

  Future<bool> enableSamba({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required String path,
    String shareName = 'USB_Storage',
  }) async {
    final cmd = 'mkdir -p "$path" && chmod 777 "$path" 2>/dev/null || true && '
        'EXISTING=\$(uci show samba4 2>/dev/null | grep -E "\\.path=\'?$path\'?" | cut -d. -f2 | head -n1); '
        'if [ -z "\$EXISTING" ]; then '
        '  SECTION=\$(uci add samba4 sambashare); '
        'else '
        '  SECTION="samba4.\$EXISTING"; '
        'fi; '
        "uci set \${SECTION}.name='$shareName'; "
        "uci set \${SECTION}.path='$path'; "
        "uci set \${SECTION}.read_only='no'; "
        "uci set \${SECTION}.guest_ok='yes'; "
        "uci set \${SECTION}.force_root='1'; "
        "uci set \${SECTION}.force_user='root'; "
        "uci set \${SECTION}.force_group='root'; "
        "uci set \${SECTION}.create_mask='0777'; "
        "uci set \${SECTION}.dir_mask='0777'; "
        "uci set \${SECTION}.force_create_mode='0777'; "
        "uci set \${SECTION}.force_directory_mode='0777'; "
        "uci set \${SECTION}.inherit_owner='yes'; "
        'uci commit samba4 && /etc/init.d/samba4 enable 2>/dev/null && /etc/init.d/samba4 restart 2>/dev/null';

    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: cmd,
    );
    return res.isSuccess;
  }

  Future<Map<String, bool>> checkPackagesStatus({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command:
          'which apk 2>/dev/null; which opkg 2>/dev/null; which block 2>/dev/null; which uqmi 2>/dev/null',
    );

    final out = res.stdout;
    return {
      'hasApk': out.contains('/apk'),
      'hasOpkg': out.contains('/opkg'),
      'hasBlock': out.contains('/block'),
      'hasModem': out.contains('/uqmi'),
    };
  }

  Future<bool> installModemPackages({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    final status = await checkPackagesStatus(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
    );

    final cmd = status['hasApk'] == true
        ? 'apk update && apk add kmod-usb-net-qmi-wwan uqmi kmod-usb-net-cdc-mbim umbim kmod-usb-net-rndis kmod-usb-serial-option usb-modeswitch'
        : 'opkg update && opkg install kmod-usb-net-qmi-wwan uqmi kmod-usb-net-cdc-mbim umbim kmod-usb-net-rndis kmod-usb-serial-option usb-modeswitch';

    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: cmd,
    );
    return res.isSuccess;
  }

  Future<bool> installStoragePackages({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    final status = await checkPackagesStatus(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
    );

    final cmd = status['hasApk'] == true
        ? 'apk update && apk add block-mount kmod-usb-storage kmod-usb-storage-uas kmod-fs-ext4 kmod-fs-ntfs3 ntfs-3g kmod-fs-vfat kmod-fs-exfat kmod-nls-base kmod-nls-utf8 kmod-nls-cp866 kmod-nls-cp1251 kmod-nls-cp437 e2fsprogs samba4-server'
        : 'opkg update && opkg install block-mount kmod-usb-storage kmod-usb-storage-uas kmod-fs-ext4 kmod-fs-ntfs3 ntfs-3g kmod-fs-vfat kmod-fs-exfat kmod-nls-base kmod-nls-utf8 kmod-nls-cp866 kmod-nls-cp1251 kmod-nls-cp437 e2fsprogs samba4-server';

    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: cmd,
    );

    if (res.isSuccess) {
      await ensureHotplugAutomountScript(
        routerIp: routerIp,
        sysauth: sysauth,
        useHttps: useHttps,
      );
    }

    return res.isSuccess;
  }

  Future<bool> ensureHotplugAutomountScript({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
  }) async {
    const hotplugScript =
        'mkdir -p /etc/hotplug.d/block && '
        'cat << \'EOF\' > /etc/hotplug.d/block/20-automount\n'
        '#!/bin/sh\n'
        '# /etc/hotplug.d/block/20-automount - Auto mount/unmount USB drives with Cyrillic & RW permissions\n'
        'case "\$ACTION" in\n'
        '    add)\n'
        '        case "\$DEVNAME" in\n'
        '            sd[a-z]*|hd[a-z]*|nvme*|mmcblk*)\n'
        '                ;;\n'
        '            *)\n'
        '                exit 0\n'
        '                ;;\n'
        '        esac\n'
        '        sleep 1\n'
        '        if [ -d "/sys/block/\$DEVNAME" ] && ls /sys/block/\$DEVNAME/\${DEVNAME}[0-9]* >/dev/null 2>&1; then\n'
        '            exit 0\n'
        '        fi\n'
        '        MOUNT_POINT="/mnt/\$DEVNAME"\n'
        '        mkdir -p "\$MOUNT_POINT"\n'
        '        FSTYPE=\$(blkid "/dev/\$DEVNAME" 2>/dev/null | grep -o \'TYPE="[^"]*"\' | cut -d\'"\' -f2)\n'
        '        if [ -z "\$FSTYPE" ]; then\n'
        '            FSTYPE=\$(block info "/dev/\$DEVNAME" 2>/dev/null | grep -o \'TYPE="[^"]*"\' | cut -d\'"\' -f2)\n'
        '        fi\n'
        '        MOUNTED=0\n'
        '        case "\$FSTYPE" in\n'
        '            *exfat*|*EXFAT*)\n'
        '                mount -t exfat -o rw,noatime,iocharset=utf8,umask=000,dmask=0000,fmask=0000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount -o rw,noatime,iocharset=utf8,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null\n'
        '                MOUNTED=\$?\n'
        '                ;;\n'
        '            *vfat*|*fat*|*FAT*)\n'
        '                mount -t vfat -o rw,noatime,iocharset=utf8,utf8=1,codepage=866,umask=000,dmask=0000,fmask=0000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount -o rw,noatime,iocharset=utf8,utf8=1,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null\n'
        '                MOUNTED=\$?\n'
        '                ;;\n'
        '            *ntfs*|*NTFS*)\n'
        '                ntfs-3g -o rw,noatime,big_writes,iocharset=utf8,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount -t ntfs3 -o rw,noatime,iocharset=utf8,umask=000,dmask=0000,fmask=0000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount -o rw,noatime,iocharset=utf8,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null\n'
        '                MOUNTED=\$?\n'
        '                ;;\n'
        '            *ext4*|*ext3*|*ext2*)\n'
        '                mount -t "\$FSTYPE" -o rw,noatime "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null\n'
        '                MOUNTED=\$?\n'
        '                ;;\n'
        '            *)\n'
        '                mount -t exfat -o rw,noatime,iocharset=utf8,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount -t vfat -o rw,noatime,iocharset=utf8,utf8=1,codepage=866,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                ntfs-3g -o rw,noatime,big_writes,iocharset=utf8,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount -t ntfs3 -o rw,noatime,iocharset=utf8,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount -o rw,noatime,iocharset=utf8,umask=000 "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null || \\\n'
        '                mount "/dev/\$DEVNAME" "\$MOUNT_POINT" 2>/dev/null\n'
        '                MOUNTED=\$?\n'
        '                ;;\n'
        '        esac\n'
        '        if [ "\$MOUNTED" -eq 0 ]; then\n'
        '            chmod 777 "\$MOUNT_POINT" 2>/dev/null || true\n'
        '            if [ -f /etc/init.d/samba4 ]; then\n'
        '                /etc/init.d/samba4 reload 2>/dev/null || /etc/init.d/samba4 restart 2>/dev/null || true\n'
        '            fi\n'
        '        fi\n'
        '        ;;\n'
        '    remove)\n'
        '        MOUNT_POINT="/mnt/\$DEVNAME"\n'
        '        if grep -qs "\$MOUNT_POINT" /proc/mounts; then\n'
        '            umount -l "\$MOUNT_POINT" 2>/dev/null || true\n'
        '        fi\n'
        '        rmdir "\$MOUNT_POINT" 2>/dev/null || true\n'
        '        ;;\n'
        'esac\n'
        'EOF\n'
        'chmod +x /etc/hotplug.d/block/20-automount 2>/dev/null; '
        '[ ! -f /etc/config/fstab ] && touch /etc/config/fstab; '
        'if ! uci get fstab.@global[0] >/dev/null 2>&1; then uci add fstab global >/dev/null 2>&1; fi; '
        'uci set fstab.@global[0].anon_mount=\'1\' 2>/dev/null; '
        'uci set fstab.@global[0].auto_mount=\'1\' 2>/dev/null; '
        'uci commit fstab 2>/dev/null';

    final res = await commandsService.execute(
      routerIp: routerIp,
      sysauth: sysauth,
      useHttps: useHttps,
      command: hotplugScript,
    );
    return res.isSuccess;
  }
}
