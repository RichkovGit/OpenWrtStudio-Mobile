import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/services/forkop_service.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/services/ota_service.dart';
import 'package:luci_mobile/widgets/ota_update_dialog.dart';

class SimpleDashboardScreen extends ConsumerStatefulWidget {
  final VoidCallback onSwitchToExpert;

  const SimpleDashboardScreen({super.key, required this.onSwitchToExpert});

  @override
  ConsumerState<SimpleDashboardScreen> createState() => _SimpleDashboardScreenState();
}

class _SimpleDashboardScreenState extends ConsumerState<SimpleDashboardScreen> {
  final ForkopService _forkopService = ForkopService(apiService: ServiceContainer.instance.factory.createApiService());
  bool _forkopActive = true;
  String _selectedPreset = 'Blanc (Основной)';
  bool _showWifiPassword = false;
  String _wifiSsid = 'Cudy_OpenWrt_5G';
  String _wifiPass = 'danik05092005';
  bool _isLoadingAction = false;
  OtaReleaseInfo? _availableOtaRelease;
  String _currentAppVer = '2.5.6';

  @override
  void initState() {
    super.initState();
    _loadInitialState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkOtaQuietly();
    });
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

  Future<void> _loadInitialState() async {
    final appState = ref.read(appStateProvider);
    final ip = appState.activeIp;
    final token = appState.sysauth;
    if (ip == null || token == null) return;
    try {
      final res = await appState.systemExec(
        command: '/bin/sh',
        params: ['-c', 'pgrep sing-box >/dev/null && echo 1 || echo 0'],
      );
      if (res is List && res.length > 1 && res[1] is Map) {
        final out = (res[1]['stdout'] ?? '').toString().trim();
        if (mounted) setState(() => _forkopActive = out.contains('1'));
      }
    } catch (_) {}
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
    final appState = ref.read(appStateProvider);
    final ip = appState.activeIp;
    final token = appState.sysauth;
    if (ip == null || token == null) return;

    setState(() => _isLoadingAction = true);
    final next = !_forkopActive;
    bool success;
    if (next) {
      success = await _forkopService.restartForkop(
        routerIp: ip, sysauth: token, useHttps: appState.useHttps,
      );
    } else {
      success = await _forkopService.stopForkop(
        routerIp: ip, sysauth: token, useHttps: appState.useHttps,
      );
    }
    setState(() {
      _isLoadingAction = false;
      if (success) _forkopActive = next;
    });
    _showMessage(success ? (next ? 'ForkOP успешно включен' : 'ForkOP остановлен') : 'Ошибка переключения ForkOP');
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
        content: const Text('Вы уверены, что хотите перезагрузить роутер? Сеть будет кратковременно недоступна (1-2 минуты).'),
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
          // Mode pill switcher
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
                    child: const Text('⚡ Простой', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
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
          await _loadInitialState();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // OTA Update Banner (if available)
            _buildOtaBanner(),

            // 1. Internet Status Card
            _buildInternetCard(isOnline),
            const SizedBox(height: 16),

            // 2. ForkOP 1-Click Master Card
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
                Text('Версия v${_availableOtaRelease!.version}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
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

  Widget _buildInternetCard(bool isOnline) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
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
                        isOnline ? 'Интернет подключен' : 'Нет подключения к сети',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOnline ? 'Шлюз 192.168.10.1 • Cudy WR3000S' : 'Проверьте соединение с роутером',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      ),
                    ],
                  ),
                ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildForkopCard() {
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
                Row(
                  children: [
                    const Icon(Icons.shield, color: Color(0xFF00D2FF), size: 24),
                    const SizedBox(width: 8),
                    const Text('ForkOP / Защита трафика', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_isLoadingAction)
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
            const SizedBox(height: 14),
            const Text('Быстрый выбор режима:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetChip('Blanc (Основной)', '🇦🇹 Вена'),
                _buildPresetChip('Stealth (Запасной)', '🛡️ Резерв'),
                _buildPresetChip('Фри (Бесплатный)', '🌐 Запас'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String name, String badge) {
    final isSelected = _selectedPreset == name;
    return ChoiceChip(
      selected: isSelected,
      selectedColor: const Color(0xFF00D2FF).withOpacity(0.25),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: TextStyle(color: isSelected ? const Color(0xFF00D2FF) : Colors.white, fontSize: 12)),
          const SizedBox(width: 4),
          Text(badge, style: const TextStyle(fontSize: 10)),
        ],
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
            const Row(
              children: [
                Icon(Icons.wifi, color: Colors.tealAccent, size: 24),
                SizedBox(width: 8),
                Text('Беспроводная сеть Wi-Fi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Имя сети (SSID):', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      Text(_wifiSsid, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Пароль Wi-Fi:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      Row(
                        children: [
                          Text(
                            _showWifiPassword ? _wifiPass : '•••••••••••••',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
                          ),
                          IconButton(
                            icon: Icon(_showWifiPassword ? Icons.visibility_off : Icons.visibility, size: 18),
                            onPressed: () => setState(() => _showWifiPassword = !_showWifiPassword),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _wifiPass));
                              _showMessage('Пароль Wi-Fi скопирован в буфер!');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
