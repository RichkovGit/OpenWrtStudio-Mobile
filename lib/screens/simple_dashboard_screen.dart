import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/services/forkop_service.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/services/ota_service.dart';
import 'package:luci_mobile/widgets/ota_update_dialog.dart';
import 'package:luci_mobile/state/app_state.dart';

class SimpleWifiNetwork {
  final String section;
  final String ssid;
  final String key;
  final String encryption;
  final String device;
  final String band;
  final bool isEnabled;
  bool showPassword;

  SimpleWifiNetwork({
    required this.section,
    required this.ssid,
    required this.key,
    required this.encryption,
    required this.device,
    required this.band,
    required this.isEnabled,
    this.showPassword = false,
  });
}

class SimpleDashboardScreen extends ConsumerStatefulWidget {
  final VoidCallback onSwitchToExpert;

  const SimpleDashboardScreen({super.key, required this.onSwitchToExpert});

  @override
  ConsumerState<SimpleDashboardScreen> createState() => _SimpleDashboardScreenState();
}

class _SimpleDashboardScreenState extends ConsumerState<SimpleDashboardScreen> {
  final ForkopService _forkopService = ForkopService(
    apiService: ServiceContainer.instance.factory.createApiService(),
  );

  // ForkOP state
  bool _isCheckingForkop = true;
  bool _isForkopInstalled = false;
  bool _forkopActive = false;
  List<String> _forkopPresets = [];
  String? _selectedPreset;
  bool _isLoadingForkopAction = false;

  // Wi-Fi state
  bool _isLoadingWifi = true;
  List<SimpleWifiNetwork> _wifiNetworks = [];

  // OTA update state
  OtaReleaseInfo? _availableOtaRelease;
  String _currentAppVer = '2.5.12';

  @override
  void initState() {
    super.initState();
    _loadAll();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkOtaQuietly();
    });
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadWifiNetworks(),
      _loadForkopState(),
    ]);
  }

  Future<void> _checkOtaQuietly() async {
    try {
      final otaService = OtaService();
      final release = await otaService.checkForUpdate();
      final currentVer = await otaService.getCurrentVersion();
      if (release != null && mounted) {
        setState(() {
          _availableOtaRelease = release;
          _currentAppVer = currentVer;
        });
      }
    } catch (_) {}
  }

  List<SimpleWifiNetwork> _parseWifiFromUciValues(Map<String, dynamic> values) {
    final radios = <String, Map<String, dynamic>>{};
    final ifaces = <String, Map<String, dynamic>>{};

    values.forEach((k, v) {
      if (v is Map) {
        final type = v['.type']?.toString();
        if (type == 'wifi-device') {
          radios[k] = Map<String, dynamic>.from(v);
        } else if (type == 'wifi-iface') {
          ifaces[k] = Map<String, dynamic>.from(v);
        }
      }
    });

    final list = <SimpleWifiNetwork>[];
    ifaces.forEach((sec, iface) {
      final mode = iface['mode']?.toString() ?? 'ap';
      if (mode != 'ap') return; // only show AP (access point) networks to users

      final ssid = iface['ssid']?.toString() ?? '';
      if (ssid.isEmpty) return;

      final key = iface['key']?.toString() ?? '';
      final encryption = iface['encryption']?.toString() ?? 'none';
      final device = iface['device']?.toString() ?? '';
      final radio = radios[device] ?? {};
      final rawBand = (radio['band']?.toString() ?? '').toLowerCase();

      String band;
      if (rawBand.contains('5g') || device.contains('radio1') || ssid.toLowerCase().contains('5g')) {
        band = '5 GHz';
      } else if (rawBand.contains('6g')) {
        band = '6 GHz';
      } else if (rawBand.contains('2g') || device.contains('radio0') || ssid.toLowerCase().contains('2.4g')) {
        band = '2.4 GHz';
      } else {
        band = 'Wi-Fi';
      }

      final isRadioDisabled = radio['disabled'] == '1' || radio['disabled'] == true;
      final isIfaceDisabled = iface['disabled'] == '1' || iface['disabled'] == true;

      list.add(SimpleWifiNetwork(
        section: sec,
        ssid: ssid,
        key: key,
        encryption: encryption,
        device: device,
        band: band,
        isEnabled: !isRadioDisabled && !isIfaceDisabled,
      ));
    });

    return list;
  }

  List<SimpleWifiNetwork> _parseWifiFromUciShow(String stdout) {
    final lines = stdout.split('\n');
    final values = <String, Map<String, dynamic>>{};

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || !line.contains('=')) continue;
      final eqIdx = line.indexOf('=');
      final left = line.substring(0, eqIdx).trim();
      var right = line.substring(eqIdx + 1).trim();
      if ((right.startsWith("'") && right.endsWith("'")) ||
          (right.startsWith('"') && right.endsWith('"'))) {
        right = right.substring(1, right.length - 1);
      }

      final parts = left.split('.');
      if (parts.length == 2 && parts[0] == 'wireless') {
        final sec = parts[1];
        values.putIfAbsent(sec, () => {})['.type'] = right;
      } else if (parts.length >= 3 && parts[0] == 'wireless') {
        final sec = parts[1];
        final opt = parts[2];
        values.putIfAbsent(sec, () => {})[opt] = right;
      }
    }

    return _parseWifiFromUciValues(values);
  }

  Future<void> _loadWifiNetworks() async {
    if (!mounted) return;
    setState(() => _isLoadingWifi = true);

    final appState = ref.read(appStateProvider);
    final ip = appState.activeIp;
    final token = appState.sysauth;

    List<SimpleWifiNetwork> networks = [];

    // 1. Check if uciWirelessConfig is already cached in dashboardData
    final uciConfig = appState.dashboardData?['uciWirelessConfig'];
    if (uciConfig is Map && uciConfig['values'] is Map) {
      networks = _parseWifiFromUciValues(Map<String, dynamic>.from(uciConfig['values'] as Map));
    }

    // 2. If empty or not loaded yet, query live router config
    if (networks.isEmpty && ip != null && token != null) {
      try {
        final res = await appState.systemExec(
          command: '/bin/sh',
          params: ['-c', 'uci -q show wireless'],
        );
        if (res is List && res.length > 1 && res[1] is Map) {
          final stdout = (res[1]['stdout'] ?? '').toString();
          networks = _parseWifiFromUciShow(stdout);
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _wifiNetworks = networks;
        _isLoadingWifi = false;
      });
    }
  }

  Future<void> _loadForkopState() async {
    final appState = ref.read(appStateProvider);
    final ip = appState.activeIp;
    final token = appState.sysauth;
    if (ip == null || token == null) {
      if (mounted) setState(() => _isCheckingForkop = false);
      return;
    }

    try {
      // 1. Check if ForkOP or Sing-box service is installed on the router
      final checkRes = await appState.systemExec(
        command: '/bin/sh',
        params: [
          '-c',
          '[ -f /etc/init.d/forkop ] || [ -f /usr/bin/forkop ] || [ -f /etc/config/forkop ] || [ -f /etc/init.d/sing-box ] && echo 1 || echo 0',
        ],
      );
      bool installed = false;
      if (checkRes is List && checkRes.length > 1 && checkRes[1] is Map) {
        final out = (checkRes[1]['stdout'] ?? '').toString().trim();
        installed = out.contains('1');
      }

      if (!installed) {
        if (mounted) {
          setState(() {
            _isForkopInstalled = false;
            _forkopActive = false;
            _forkopPresets = [];
            _isCheckingForkop = false;
          });
        }
        return;
      }

      // 2. Check if proxy daemon process is currently running
      final runRes = await appState.systemExec(
        command: '/bin/sh',
        params: ['-c', 'pgrep -f "sing-box|forkop|mihomo" >/dev/null && echo 1 || echo 0'],
      );
      bool active = false;
      if (runRes is List && runRes.length > 1 && runRes[1] is Map) {
        final out = (runRes[1]['stdout'] ?? '').toString().trim();
        active = out.contains('1');
      }

      // 3. Fetch real nodes / profiles from router
      List<String> presets = [];
      try {
        final nodes = await _forkopService.fetchNodes(
          routerIp: ip,
          sysauth: token,
          useHttps: appState.useHttps,
        );
        presets = nodes.map<String>((n) => n.displayTitle).where((s) => s.isNotEmpty).take(6).toList();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isForkopInstalled = true;
          _forkopActive = active;
          _forkopPresets = presets;
          if (presets.isNotEmpty && (_selectedPreset == null || !presets.contains(_selectedPreset))) {
            _selectedPreset = presets.first;
          }
          _isCheckingForkop = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isForkopInstalled = false;
          _forkopActive = false;
          _isCheckingForkop = false;
        });
      }
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _toggleForkopMaster() async {
    if (!_isForkopInstalled) return;
    final appState = ref.read(appStateProvider);
    final ip = appState.activeIp;
    final token = appState.sysauth;
    if (ip == null || token == null) return;

    setState(() => _isLoadingForkopAction = true);
    final next = !_forkopActive;
    bool success;
    if (next) {
      success = await _forkopService.restartForkop(
        routerIp: ip,
        sysauth: token,
        useHttps: appState.useHttps,
      );
    } else {
      success = await _forkopService.stopForkop(
        routerIp: ip,
        sysauth: token,
        useHttps: appState.useHttps,
      );
    }
    if (mounted) {
      setState(() {
        _isLoadingForkopAction = false;
        if (success) _forkopActive = next;
      });
      _showMessage(
        success
            ? (next ? 'Защита трафика успешно включена' : 'Защита трафика остановлена')
            : 'Ошибка переключения службы',
      );
    }
  }

  Future<void> _confirmReboot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restart_alt, color: Colors.orange),
            SizedBox(width: 8),
            Text('Перезагрузка роутера'),
          ],
        ),
        content: const Text(
          'Вы уверены, что хотите перезагрузить роутер? Сеть будет кратковременно недоступна (1-2 минуты).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Перезагрузить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final appState = ref.read(appStateProvider);
      await appState.reboot();
      _showMessage('Команда на перезагрузку отправлена');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final isOnline = appState.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.router, size: 24, color: Color(0xFF00D2FF)),
            SizedBox(width: 10),
            Text('OpenWrt Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          // Mode switcher
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D2FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '⚡ Простой',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onSwitchToExpert,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: const Text('🛠️ Эксперт', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.fetchDashboardData();
          await _loadAll();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // OTA Update Banner
            _buildOtaBanner(),

            // 1. Internet & Router Status Card
            _buildInternetCard(isOnline, appState),
            const SizedBox(height: 16),

            // 2. ForkOP / Traffic Protection Card
            _buildForkopCard(),
            const SizedBox(height: 16),

            // 3. Quick Wi-Fi Card
            _buildWifiCard(),
            const SizedBox(height: 16),

            // 4. Quick Help & Actions Card
            _buildQuickActionsCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildOtaBanner() {
    if (_availableOtaRelease == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F2A38),
            Color(0xFF13384D),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00D2FF).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00D2FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update, color: Color(0xFF00D2FF), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Доступно обновление!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  'Версия v${_availableOtaRelease!.version}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2FF),
              foregroundColor: Colors.black,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              OtaUpdateDialog.show(
                context,
                releaseInfo: _availableOtaRelease!,
                currentVersion: _currentAppVer,
              );
            },
            child: const Text('Обновить', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildInternetCard(bool isOnline, AppState appState) {
    final routerIp = appState.activeIp ?? '192.168.1.1';
    final boardInfo = appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final modelRaw = boardInfo?['model']?.toString();
    final hostnameRaw = boardInfo?['hostname']?.toString();
    final routerName = appState.selectedRouter?.lastKnownHostname;

    String routerInfoStr;
    if (modelRaw != null && modelRaw.isNotEmpty) {
      routerInfoStr = modelRaw;
      if (hostnameRaw != null &&
          hostnameRaw.isNotEmpty &&
          hostnameRaw != 'OpenWrt' &&
          hostnameRaw != modelRaw) {
        routerInfoStr += ' ($hostnameRaw)';
      }
    } else if (routerName != null && routerName.isNotEmpty) {
      routerInfoStr = routerName;
    } else {
      routerInfoStr = 'OpenWrt Router';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isOnline ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOnline ? Icons.public : Icons.public_off,
                color: isOnline ? Colors.greenAccent : Colors.redAccent,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOnline ? 'Подключено к роутеру' : 'Нет подключения к сети',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline
                        ? 'Шлюз $routerIp • $routerInfoStr'
                        : 'Проверьте соединение с роутером ($routerIp)',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isOnline ? Colors.green.shade900 : Colors.red.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isOnline ? 'В СЕТИ' : 'ОФЛАЙН',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForkopCard() {
    if (_isCheckingForkop) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (!_isForkopInstalled) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield_outlined, color: Colors.blueGrey, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ForkOP / Защита трафика',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Служба не установлена на роутере',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Пакет ForkOP или Sing-box не обнаружен на данной прошивке. Для настройки сети, Wi-Fi и фаервола используйте Экспертный режим.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00D2FF),
                    side: const BorderSide(color: Color(0xFF00D2FF)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Перейти в Экспертный режим'),
                  onPressed: widget.onSwitchToExpert,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield, color: Color(0xFF00D2FF), size: 24),
                    SizedBox(width: 8),
                    Text('ForkOP / Защита трафика', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_isLoadingForkopAction)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Switch(
                    value: _forkopActive,
                    activeColor: const Color(0xFF00D2FF),
                    onChanged: (_) => _toggleForkopMaster(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _forkopActive
                  ? 'Обход блокировок и маршрутизация активны'
                  : 'Трафик идёт напрямую через провайдера без прокси',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            if (_forkopPresets.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Выбор профиля:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _forkopPresets.map((preset) => _buildPresetChip(preset)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String name) {
    final isSelected = _selectedPreset == name;
    return ChoiceChip(
      selected: isSelected,
      selectedColor: const Color(0xFF00D2FF).withValues(alpha: 0.25),
      label: Text(
        name,
        style: TextStyle(
          color: isSelected ? const Color(0xFF00D2FF) : Colors.white,
          fontSize: 12,
        ),
      ),
      onSelected: (val) {
        if (val) {
          setState(() => _selectedPreset = name);
          _showMessage('Выбран профиль: $name');
        }
      },
    );
  }

  Widget _buildWifiCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wifi, color: Colors.tealAccent, size: 24),
                    SizedBox(width: 8),
                    Text('Беспроводная сеть Wi-Fi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_isLoadingWifi)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingWifi && _wifiNetworks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Загрузка параметров Wi-Fi...',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              )
            else if (_wifiNetworks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.grey, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Точки доступа Wi-Fi не настроены или модуль отключен',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: _wifiNetworks.map((net) => _buildSingleWifiItem(net)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleWifiItem(SimpleWifiNetwork net) {
    final hasPassword = net.key.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.wifi, color: Color(0xFF00D2FF), size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        net.ssid,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  net.band,
                  style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 16, color: Color(0xFF1E293B)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Пароль:', style: TextStyle(color: Colors.grey, fontSize: 13)),
              if (!hasPassword)
                const Text(
                  'Без пароля (Открытая сеть)',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontStyle: FontStyle.italic),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      net.showPassword ? net.key : '••••••••••••',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
                    ),
                    IconButton(
                      icon: Icon(net.showPassword ? Icons.visibility_off : Icons.visibility, size: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          net.showPassword = !net.showPassword;
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: net.key));
                        _showMessage('Пароль от "${net.ssid}" скопирован!');
                      },
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Быстрые действия', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Перезагрузка'),
                    onPressed: _confirmReboot,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00D2FF),
                      side: const BorderSide(color: Color(0xFF00D2FF)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.build_outlined),
                    label: const Text('Все опции (Эксперт)'),
                    onPressed: widget.onSwitchToExpert,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
