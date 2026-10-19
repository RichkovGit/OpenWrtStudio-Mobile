import 'dart:io';
import 'package:luci_mobile/screens/simple_dashboard_screen.dart';
import 'package:luci_mobile/services/router_watchdog_service.dart';
import 'package:luci_mobile/utils/url_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/navigation/luci_tab.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/insights_screen.dart';
import 'package:luci_mobile/screens/network_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/widgets/luci_navigation_enhancements.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  final LuciTab? initialTab;
  final String? interfaceToScroll;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  bool _isForeground = true;
  String? _routerEndpoint(String address, bool useHttps) {
    var input = address.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(input)) {
      // A bare IPv6 literal has no port suffix, matching the API client's rule.
      if (!input.startsWith('[') && ':'.allMatches(input).length > 1) {
        input = '[$input]';
      }
      input = '${useHttps ? 'https' : 'http'}://$input';
    } else {
      input = input.replaceFirstMapped(
        RegExp(r'^https?://', caseSensitive: false),
        (match) => match[0]!.toLowerCase(),
      );
    }
    final parsed = UrlParser.parse(input);
    if (!parsed.isValid) return null;
    var host = parsed.host.toLowerCase();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    final addressValue = InternetAddress.tryParse(host);
    host = addressValue == null
        ? 'dns/$host'
        : '${addressValue.type == InternetAddressType.IPv6 ? 'ip6' : 'ip4'}/'
              '${addressValue.rawAddress.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
    return '${parsed.useHttps}:[$host]:${parsed.port}';
  }

  void _syncWatchdog() {
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    final ip = appState.activeIp;
    final token = appState.sysauth;
    final selectedRouter = appState.selectedRouter;
    final authEndpoint = ip == null
        ? null
        : _routerEndpoint(ip, appState.useHttps);
    final selectedEndpoint = selectedRouter == null
        ? null
        : _routerEndpoint(
            selectedRouter.activeAddress,
            selectedRouter.activeUseHttps,
          );
    if (!_isForeground ||
        !appState.isAuthenticated ||
        ip == null ||
        ip.trim().isEmpty ||
        token == null ||
        token.isEmpty ||
        (selectedRouter != null &&
            (authEndpoint == null || selectedEndpoint != authEndpoint))) {
      RouterWatchdogService.instance.stopMonitoring();
      return;
    }
    RouterWatchdogService.instance.startMonitoring(
      routerIp: ip,
      sysauth: token,
      useHttps: appState.useHttps,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    _syncWatchdog();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RouterWatchdogService.instance.stopMonitoring();
    super.dispose();
  }

  LuciTab _selected = LuciTab.dashboard;
  String? _pendingInterface;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWatchdog();
    });
    if (widget.initialTab != null) _selected = widget.initialTab!;
    _pendingInterface = widget.interfaceToScroll;
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _pendingInterface = widget.interfaceToScroll;
    }
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selected = widget.initialTab!;
    }
  }

  void _clearPendingInterface() {
    if (_pendingInterface == null) return;
    setState(() => _pendingInterface = null);
  }

  Widget _bodyFor(LuciTab tab) => switch (tab) {
    LuciTab.dashboard => const DashboardScreen(),
    LuciTab.network => NetworkScreen(
      pendingInterface: _pendingInterface,
      onConsumed: _clearPendingInterface,
    ),
    LuciTab.clients => const ClientsScreen(),
    LuciTab.insights => const InsightsScreen(),
    LuciTab.settings => const SettingsScreen(),
  };

  void _select(LuciTab tab) {
    setState(() => _selected = tab);
    if (tab != LuciTab.network) _clearPendingInterface();
  }

  ({IconData filled, IconData outlined, String label}) _destination(
    LuciTab tab,
    BuildContext context,
  ) {
    final l10n = context.l10n;
    return switch (tab) {
      LuciTab.dashboard => (
        filled: Icons.dashboard,
        outlined: Icons.dashboard_outlined,
        label: l10n.dashboard,
      ),
      LuciTab.network => (
        filled: Icons.lan,
        outlined: Icons.lan_outlined,
        label: l10n.network,
      ),
      LuciTab.clients => (
        filled: Icons.people,
        outlined: Icons.people_outline,
        label: l10n.clients,
      ),
      LuciTab.insights => (
        // `insights` is a chart with a sparkle on it, which now reads as
        // "AI" rather than "logs, traffic and diagnostics". A vitals line
        // says what this tab actually holds.
        filled: Icons.monitor_heart,
        outlined: Icons.monitor_heart_outlined,
        label: l10n.insights,
      ),
      LuciTab.settings => (
        filled: Icons.settings,
        outlined: Icons.settings_outlined,
        label: l10n.settings,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appStateProvider, (_, _) => _syncWatchdog());
    final appState = ref.watch(appStateProvider);

    // The dashboard asks for a tab by name; honour it after this frame so the
    // request can be cleared without rebuilding mid-build.
    if (appState.requestedTab != null) {
      final requested = appState.requestedTab!;
      final requestedInterface = appState.requestedInterfaceToScroll;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Cleared whatever happens: a request left standing replays on the
        // next mount, jumping the user to a tab they asked for before
        // logging out - or latches when it names the tab already showing.
        if (appState.requestedTab != requested ||
            appState.requestedInterfaceToScroll != requestedInterface)
          return;
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
        if (!mounted) return;
        setState(() {
          _selected = requested;
          if (requestedInterface != null) {
            _pendingInterface = requestedInterface;
          }
        });
      });
    }

    if (!appState.isExpertMode) {
      return SimpleDashboardScreen(
        onSwitchToExpert: () => appState.setExpertMode(true),
      );
    }
    return Scaffold(
      body: LuciTabTransition(
        transitionKey: 'tab_${_selected.name}',
        child: _bodyFor(_selected),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isRebooting = ref.watch(
            appStateProvider.select((state) => state.isRebooting),
          );
          final scheme = Theme.of(context).colorScheme;

          return NavigationBar(
            // Five labels overflow in German and Russian at narrow widths;
            // showing only the selected one keeps them readable without
            // truncating.
            labelBehavior: MediaQuery.sizeOf(context).width < 400
                ? NavigationDestinationLabelBehavior.onlyShowSelected
                : NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: _selected.index,
            onDestinationSelected: (index) {
              final tab = LuciTab.fromIndex(index);
              if (isRebooting && !tab.allowedDuringReboot) return;
              _select(tab);
            },
            destinations: [
              for (final tab in LuciTab.values)
                _buildDestination(context, tab, isRebooting, scheme),
            ],
          );
        },
      ),
    );
  }

  NavigationDestination _buildDestination(
    BuildContext context,
    LuciTab tab,
    bool isRebooting,
    ColorScheme scheme,
  ) {
    final d = _destination(tab, context);
    final locked = isRebooting && !tab.allowedDuringReboot;
    // Grey is only correct in a light theme; the disabled tone has to come
    // from the scheme or the bar looks broken in dark mode.
    final lockedColor = scheme.onSurface.withValues(alpha: 0.38);

    Widget wrap(IconData icon) => Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: Icon(icon, color: locked ? lockedColor : null),
    );

    return NavigationDestination(
      selectedIcon: wrap(d.filled),
      icon: wrap(d.outlined),
      label: d.label,
      tooltip: locked ? context.l10n.rebootingConnectionInterrupted : d.label,
    );
  }
}
