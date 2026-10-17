import 'dart:io';

import 'package:flutter/material.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/more_screen.dart';
import 'package:luci_mobile/screens/simple_dashboard_screen.dart';
import 'package:luci_mobile/services/router_watchdog_service.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_navigation_enhancements.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/utils/url_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;

  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String? _currentInterfaceToScroll;
  bool _isForeground = true;

  int _validTab(int index) => index >= 0 && index < 4 ? index : 0;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    if (widget.initialTab != null) {
      _selectedIndex = _validTab(widget.initialTab!);
    }
    _currentInterfaceToScroll = widget.interfaceToScroll;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWatchdog();
    });
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

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle parameter changes (important for iOS navigation)
    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _currentInterfaceToScroll = widget.interfaceToScroll;
    }

    // Handle initial tab changes
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = _validTab(widget.initialTab!);
    }
  }

  void _clearInterfaceToScroll() {
    if (_currentInterfaceToScroll != null) {
      setState(() {
        _currentInterfaceToScroll = null;
      });
    }
  }

  List<Widget> get _widgetOptions => [
    const DashboardScreen(),
    const ClientsScreen(),
    InterfacesScreen(
      scrollToInterface: _currentInterfaceToScroll,
      onScrollComplete: _clearInterfaceToScroll,
    ),
    const MoreScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Clear interface scroll state when navigating away from Interfaces tab
    if (_selectedIndex != 2 && _currentInterfaceToScroll != null) {
      _clearInterfaceToScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appStateProvider, (_, _) => _syncWatchdog());
    // Listen for requestedTab in AppState
    final appState = ref.watch(appStateProvider);
    if (appState.requestedTab != null) {
      // Store the values before the callback to avoid null reference issues
      final requestedTab = appState.requestedTab!;
      final requestedInterface = appState.requestedInterfaceToScroll;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            appState.requestedTab != requestedTab ||
            appState.requestedInterfaceToScroll != requestedInterface) {
          return;
        }
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
        setState(() {
          _selectedIndex = _validTab(requestedTab);
          // Update interface to scroll if provided
          if (requestedInterface != null) {
            _currentInterfaceToScroll = requestedInterface;
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
      body: Center(
        child: LuciTabTransition(
          transitionKey: 'tab_$_selectedIndex',
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isRebooting = ref.watch(
            appStateProvider.select((state) => state.isRebooting),
          );
          Color? getTabColor(int index) =>
              (isRebooting && index != 3) ? Colors.grey.withAlpha(128) : null;
          double getTabOpacity(int index) =>
              (isRebooting && index != 3) ? 0.5 : 1.0;
          return NavigationBar(
            onDestinationSelected: (index) {
              if (isRebooting && index != 3) return; // Only allow 'More' tab
              _onItemTapped(index);
            },
            selectedIndex: _selectedIndex,
            destinations: [
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard, color: getTabColor(0)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard_outlined, color: getTabColor(0)),
                ),
                label: context.l10n.dashboard,
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.people, color: getTabColor(1)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.people_outline, color: getTabColor(1)),
                ),
                label: context.l10n.clients,
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.lan, color: getTabColor(2)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.lan_outlined, color: getTabColor(2)),
                ),
                label: context.l10n.interfaces,
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(3),
                  child: Icon(Icons.more_horiz),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(3),
                  child: Icon(Icons.more_horiz_outlined),
                ),
                label: context.l10n.more,
              ),
            ],
          );
        },
      ),
    );
  }
}
