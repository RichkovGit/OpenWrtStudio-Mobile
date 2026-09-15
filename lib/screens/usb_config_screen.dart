import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/models/usb_models.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/services/usb_config_service.dart';
import 'package:luci_mobile/main.dart';

class UsbConfigScreen extends ConsumerStatefulWidget {
  const UsbConfigScreen({super.key});

  @override
  ConsumerState<UsbConfigScreen> createState() => _UsbConfigScreenState();
}

class _UsbConfigScreenState extends ConsumerState<UsbConfigScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late UsbConfigService _usbService;

  bool _isLoading = false;
  String _statusMessage = '';
  List<UsbDeviceItem> _usbDevices = [];
  List<UsbDiskPartition> _disks = [];
  UsbModemProfile _modem = const UsbModemProfile();

  final _apnController = TextEditingController();
  final _deviceController = TextEditingController();
  final _pinController = TextEditingController();

  final List<String> _protocols = ['qmi', 'mbim', 'ncm', 'rndis', '3g'];
  final List<String> _pdpTypes = ['ipv4', 'ipv6', 'ipv4v6'];
  final List<String> _authTypes = ['none', 'pap', 'chap'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _usbService = UsbConfigService(apiService: ServiceFactory.apiService);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apnController.dispose();
    _deviceController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final appState = ref.read(appStateProvider);
    final ip = appState.activeIp ?? '';
    final token = appState.sysauth;
    final useHttps = appState.useHttps;

    if (token == null || token.isEmpty || ip.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Сканирование USB шины роутера...';
    });

    try {
      final devices = await _usbService.getUsbDevices(
        routerIp: ip,
        sysauth: token,
        useHttps: useHttps,
      );
      final disks = await _usbService.getStorageDisks(
        routerIp: ip,
        sysauth: token,
        useHttps: useHttps,
      );
      final modem = await _usbService.getModemProfile(
        routerIp: ip,
        sysauth: token,
        useHttps: useHttps,
      );

      _apnController.text = modem.apn;
      _deviceController.text = modem.deviceNode;
      _pinController.text = modem.pinCode;

      setState(() {
        _usbDevices = devices;
        _disks = disks;
        _modem = modem;
        _statusMessage = devices.isNotEmpty
            ? 'Найдено ${devices.length} USB устройств, ${disks.length} разделов'
            : 'Физические USB устройства не обнаружены (порт свободен)';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Ошибка загрузки: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveModem() async {
    final appState = ref.read(appStateProvider);
    setState(() => _isLoading = true);

    final updated = _modem.copyWith(
      apn: _apnController.text.trim(),
      deviceNode: _deviceController.text.trim(),
      pinCode: _pinController.text.trim(),
    );

    final success = await _usbService.saveModemProfile(
      routerIp: appState.activeIp ?? '',
      sysauth: appState.sysauth ?? '',
      useHttps: appState.useHttps,
      profile: updated,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              success ? 'Конфигурация модема сохранена' : 'Ошибка сохранения'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    await _loadData();
  }

  Future<void> _restartModem() async {
    final appState = ref.read(appStateProvider);
    setState(() => _isLoading = true);

    final success = await _usbService.restartModemInterface(
      routerIp: appState.activeIp ?? '',
      sysauth: appState.sysauth ?? '',
      useHttps: appState.useHttps,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              success ? 'Интерфейс модема перезапущен' : 'Ошибка перезапуска'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    await Future.delayed(const Duration(seconds: 2));
    await _loadData();
  }

  Future<void> _mountDisk(UsbDiskPartition disk) async {
    final appState = ref.read(appStateProvider);
    setState(() => _isLoading = true);

    final target = disk.mountPoint.isNotEmpty
        ? disk.mountPoint
        : '/mnt/${disk.deviceNode.replaceAll('/dev/', '')}';

    final success = await _usbService.mountDisk(
      routerIp: appState.activeIp ?? '',
      sysauth: appState.sysauth ?? '',
      useHttps: appState.useHttps,
      deviceNode: disk.deviceNode,
      mountPoint: target,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              success ? 'Диск смонтирован в $target' : 'Ошибка монтирования'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    await _loadData();
  }

  Future<void> _unmountDisk(UsbDiskPartition disk) async {
    final appState = ref.read(appStateProvider);
    setState(() => _isLoading = true);

    final target =
        disk.mountPoint.isNotEmpty ? disk.mountPoint : disk.deviceNode;
    final success = await _usbService.unmountDisk(
      routerIp: appState.activeIp ?? '',
      sysauth: appState.sysauth ?? '',
      useHttps: appState.useHttps,
      mountPoint: target,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? 'Диск размонтирован' : 'Ошибка размонтирования'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    await _loadData();
  }

  Future<void> _enableSamba(UsbDiskPartition disk) async {
    final appState = ref.read(appStateProvider);
    if (disk.mountPoint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала смонтируйте накопитель')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final success = await _usbService.enableSamba(
      routerIp: appState.activeIp ?? '',
      sysauth: appState.sysauth ?? '',
      useHttps: appState.useHttps,
      path: disk.mountPoint,
      shareName: disk.label.isNotEmpty ? disk.label : 'USB_Share',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Общий доступ Samba включен'
              : 'Ошибка настройки Samba'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    await _loadData();
  }

  Future<void> _installModemPackages() async {
    final appState = ref.read(appStateProvider);
    setState(() {
      _isLoading = true;
      _statusMessage = 'Установка пакетов для модемов...';
    });

    final success = await _usbService.installModemPackages(
      routerIp: appState.activeIp ?? '',
      sysauth: appState.sysauth ?? '',
      useHttps: appState.useHttps,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Пакеты модемов успешно установлены'
              : 'Сбой установки пакетов'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    await _loadData();
  }

  Future<void> _installStoragePackages() async {
    final appState = ref.read(appStateProvider);
    setState(() {
      _isLoading = true;
      _statusMessage = 'Установка пакетов для дисков и Samba...';
    });

    final success = await _usbService.installStoragePackages(
      routerIp: appState.activeIp ?? '',
      sysauth: appState.sysauth ?? '',
      useHttps: appState.useHttps,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Пакеты хранилища успешно установлены'
              : 'Сбой установки пакетов'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('USB Устройства'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade800,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('BETA',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.cell_tower), text: 'Модемы (LTE)'),
            Tab(icon: Icon(Icons.storage), text: 'Диски и Samba'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Beta Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.amber.shade900.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(Icons.science, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Экспериментальная функция для роутеров с USB портом. '
                    '$_statusMessage',
                    style: const TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildModemsTab(theme),
                _buildDisksTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModemsTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_usbDevices.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Физические USB устройства',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ..._usbDevices.map((dev) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            dev.deviceType == 'Модем'
                                ? Icons.cell_tower
                                : Icons.usb,
                            color: Colors.amber),
                        title: Text(dev.name,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text('ID: ${dev.id} | Тип: ${dev.deviceType}',
                            style: const TextStyle(fontSize: 12)),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Status Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Состояние мобильного модема',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Статус',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(_modem.status,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _modem.isUp
                                      ? Colors.green
                                      : Colors.orange)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Сигнал (RSSI)',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(_modem.signalStrength,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Config Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Параметры подключения',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 14),

                // Protocol Dropdown
                DropdownButtonFormField<String>(
                  value: _protocols.contains(_modem.protocol)
                      ? _modem.protocol
                      : 'qmi',
                  decoration: const InputDecoration(
                      labelText: 'Протокол модема',
                      border: OutlineInputBorder()),
                  items: _protocols
                      .map((p) => DropdownMenuItem(
                          value: p, child: Text(p.toUpperCase())))
                      .toList(),
                  onChanged: (val) {
                    if (val != null)
                      setState(() => _modem = _modem.copyWith(protocol: val));
                  },
                ),
                const SizedBox(height: 12),

                // Device Node
                TextField(
                  controller: _deviceController,
                  decoration: const InputDecoration(
                    labelText: 'Узел устройства (/dev)',
                    helperText: 'Обычно /dev/cdc-wdm0 или /dev/ttyUSB0',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // APN
                TextField(
                  controller: _apnController,
                  decoration: const InputDecoration(
                    labelText: 'Точка доступа (APN)',
                    helperText: 'Например: internet, internet.mts.ru, yota.ru',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // PDP Type
                DropdownButtonFormField<String>(
                  value: _pdpTypes.contains(_modem.pdpType)
                      ? _modem.pdpType
                      : 'ipv4',
                  decoration: const InputDecoration(
                      labelText: 'Тип PDP (Стек IP)',
                      border: OutlineInputBorder()),
                  items: _pdpTypes
                      .map((p) => DropdownMenuItem(
                          value: p, child: Text(p.toUpperCase())))
                      .toList(),
                  onChanged: (val) {
                    if (val != null)
                      setState(() => _modem = _modem.copyWith(pdpType: val));
                  },
                ),
                const SizedBox(height: 12),

                // Auth Type
                DropdownButtonFormField<String>(
                  value: _authTypes.contains(_modem.authType)
                      ? _modem.authType
                      : 'none',
                  decoration: const InputDecoration(
                      labelText: 'Тип авторизации',
                      border: OutlineInputBorder()),
                  items: _authTypes
                      .map((a) => DropdownMenuItem(
                          value: a, child: Text(a.toUpperCase())))
                      .toList(),
                  onChanged: (val) {
                    if (val != null)
                      setState(() => _modem = _modem.copyWith(authType: val));
                  },
                ),
                const SizedBox(height: 12),

                // PIN Code
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'PIN-код SIM (опционально)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Сохранить'),
                        onPressed: _isLoading ? null : _saveModem,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Перезапуск'),
                        onPressed: _isLoading ? null : _restartModem,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 1-Click Install Card
        Card(
          child: ListTile(
            leading: const Icon(Icons.download, color: Colors.blue),
            title: const Text('Установить драйверы модемов'),
            subtitle:
                const Text('kmod-usb-net-qmi-wwan, uqmi, mbim, modeswitch'),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _isLoading ? null : _installModemPackages,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisksTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_disks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: const [
                  Icon(Icons.usb_off, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Диски не найдены',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 6),
                  Text(
                    'Подключите USB накопитель или флешку в разъем роутера.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          ..._disks.map((disk) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storage, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(disk.deviceNode,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(disk.fileSystem,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: disk.isMounted
                                ? Colors.green.shade800
                                : Colors.grey.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            disk.isMounted ? 'Смонтирован' : 'Не активен',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (disk.mountPoint.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Точка монтирования: ${disk.mountPoint}',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                    ],
                    if (disk.isMounted) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                          value: (disk.usagePercentage / 100).clamp(0.0, 1.0)),
                      const SizedBox(height: 4),
                      Text(
                          '${disk.usedSize} / ${disk.totalSize} (${disk.usagePercentage.toStringAsFixed(0)}%)',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (!disk.isMounted)
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Смонтировать'),
                              onPressed:
                                  _isLoading ? null : () => _mountDisk(disk),
                            ),
                          )
                        else ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.folder_off),
                              label: const Text('Размонтировать'),
                              onPressed:
                                  _isLoading ? null : () => _unmountDisk(disk),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.share),
                              label: const Text('Samba Шара'),
                              onPressed:
                                  _isLoading ? null : () => _enableSamba(disk),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: 16),
        // 1-Click Install Storage Packages Card
        Card(
          child: ListTile(
            leading: const Icon(Icons.download, color: Colors.green),
            title: const Text('Установить пакеты для USB дисков'),
            subtitle:
                const Text('block-mount, kmod-usb-storage, ext4, ntfs, samba4'),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _isLoading ? null : _installStoragePackages,
            ),
          ),
        ),
      ],
    );
  }
}
