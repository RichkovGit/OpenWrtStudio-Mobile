import 'package:flutter/material.dart';
import 'package:luci_mobile/screens/log_screen.dart';

/// Studio and standard navigation share the same checked log reader.
class SystemLogsScreen extends StatelessWidget {
  const SystemLogsScreen({super.key});

  @override
  Widget build(BuildContext context) => const LogScreen();
}
