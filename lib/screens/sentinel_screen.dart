import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/sentinel_fix_report.dart';
import 'package:luci_mobile/models/sentinel_target.dart';
import 'package:luci_mobile/services/sentinel_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';

class SentinelScreen extends ConsumerStatefulWidget {
  const SentinelScreen({super.key});

  @override
  ConsumerState<SentinelScreen> createState() => _SentinelScreenState();
}

class _SentinelScreenState extends ConsumerState<SentinelScreen> {
  List<SentinelTarget> _targets = SentinelTarget.defaultTargets();
  bool _isChecking = false;
  bool _isFixing = false;
  Object? _checkError;
  int _fixStepIndex = 0;
  int _fixStepCount = SentinelService.fixSteps.length;
  String _fixStepId = SentinelService.fixSteps.first.id;

  @override
  void initState() {
    super.initState();
    // The session may not exist yet (login in flight); the listener in
    // build starts the check once it appears.
    Future.microtask(_checkHealth);
  }

  String _stepName(String id) {
    final l10n = context.l10n;
    return switch (id) {
      'dns' => l10n.sentinelFixStepDns,
      'bypass' => l10n.sentinelFixStepBypass,
      'firewall' => l10n.sentinelFixStepFirewall,
      _ => id,
    };
  }

  String _statusName(SentinelStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      SentinelStatus.online => l10n.sentinelStatusOnline,
      SentinelStatus.blocked => l10n.sentinelStatusBlocked,
      SentinelStatus.timeout => l10n.sentinelStatusTimeout,
      SentinelStatus.pending => l10n.sentinelStatusPending,
      SentinelStatus.unknown => l10n.sentinelStatusUnknown,
    };
  }

  Future<void> _checkHealth() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null || _isChecking) return;

    setState(() {
      _isChecking = true;
      _checkError = null;
    });

    try {
      final updated = await SentinelService(apiService: api).checkConnectivity(
        routerIp: session.ipAddress,
        sysauth: session.sysauth,
        useHttps: session.useHttps,
        customTargets: _targets,
      );
      // A router switch mid-probe must not show the old router's answers
      // as the new one's connectivity.
      if (mounted && ref.read(sessionProvider) == session) {
        setState(() => _targets = updated);
      }
    } catch (e) {
      if (mounted && ref.read(sessionProvider) == session) {
        setState(() => _checkError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
        // A switch mid-probe skipped the listener's re-check (one was
        // already running); now that the slot is free, check the new router.
        if (ref.read(sessionProvider) != session) {
          unawaited(Future.microtask(_checkHealth));
        }
      }
    }
  }

  Future<void> _runFixAll() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null || _isFixing) return;

    setState(() {
      _isFixing = true;
      _fixStepIndex = 0;
      _fixStepCount = SentinelService.fixSteps.length;
      _fixStepId = SentinelService.fixSteps.first.id;
    });

    final SentinelFixReport report;
    try {
      report = await SentinelService(apiService: api).autoFixAll(
        routerIp: session.ipAddress,
        sysauth: session.sysauth,
        useHttps: session.useHttps,
        onProgress: (index, count, id) {
          if (mounted && ref.read(sessionProvider) == session) {
            setState(() {
              _fixStepIndex = index;
              _fixStepCount = count;
              _fixStepId = id;
            });
          }
        },
      );
    } finally {
      if (mounted) setState(() => _isFixing = false);
    }

    if (!mounted || ref.read(sessionProvider) != session) {
      return;
    }
    await _showFixReport(report);
    if (mounted && ref.read(sessionProvider) == session) {
      await _checkHealth();
    }
  }

  Future<void> _showFixReport(SentinelFixReport report) async {
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.sentinelFixReportTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final step in report.steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          switch (step.status) {
                            SentinelFixStatus.fixed => Icons.check_circle,
                            SentinelFixStatus.failed => Icons.error,
                            SentinelFixStatus.skipped =>
                              Icons.remove_circle_outline,
                          },
                          size: 20,
                          color: switch (step.status) {
                            SentinelFixStatus.fixed => Colors.green,
                            SentinelFixStatus.failed => theme.colorScheme.error,
                            SentinelFixStatus.skipped =>
                              theme.colorScheme.onSurfaceVariant,
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_stepName(step.id)),
                              Text(
                                switch (step.status) {
                                      SentinelFixStatus.fixed =>
                                        l10n.sentinelFixFixed,
                                      SentinelFixStatus.failed =>
                                        l10n.sentinelFixFailed,
                                      SentinelFixStatus.skipped =>
                                        l10n.sentinelFixSkipped,
                                    } +
                                    (step.detail != null
                                        ? ' (${step.detail})'
                                        : ''),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  l10n.sentinelFixSummary(
                    report.fixedCount,
                    report.failedCount,
                    report.skippedCount,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider);

    // A new session (router switch, re-login, logout) invalidates whatever
    // the previous router answered; re-check against the new one.
    ref.listen<RouterSession?>(sessionProvider, (previous, next) {
      if (next == previous) return;
      _checkError = null;
      _targets = [
        for (final t in _targets)
          t.copyWith(status: SentinelStatus.unknown, latencyMs: null),
      ];
      if (next != null) _checkHealth();
    });

    final onlineCount = _targets
        .where((t) => t.status == SentinelStatus.online)
        .length;
    final totalCount = _targets.length;
    final allGood = onlineCount == totalCount;

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n.sentinelTitle,
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isChecking || session == null ? null : _checkHealth,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _checkHealth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LuciSpacing.md,
              LuciSpacing.md,
              LuciSpacing.md,
              36,
            ),
            children: [
              // Status Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: LuciCardStyles.standardRadius,
                  side: BorderSide(
                    color: allGood
                        ? Colors.green.withAlpha(120)
                        : Colors.orange.withAlpha(120),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(LuciSpacing.md),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: allGood
                                ? Colors.green.withAlpha(30)
                                : Colors.orange.withAlpha(30),
                            child: Icon(
                              allGood
                                  ? Icons.verified_user
                                  : Icons.warning_amber_rounded,
                              color: allGood ? Colors.green : Colors.orange,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    allGood
                                        ? l10n.sentinelAllGood
                                        : l10n.sentinelIssuesFound,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.sentinelTargetsAvailable(
                                    onlineCount,
                                    totalCount,
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: _isChecking || session == null
                                  ? null
                                  : _checkHealth,
                              icon: _isChecking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.speed, size: 18),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(l10n.sentinelCheck, maxLines: 1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed:
                                  _isFixing || _isChecking || session == null
                                  ? null
                                  : _runFixAll,
                              icon: _isFixing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.build_circle, size: 18),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(l10n.sentinelFixAll, maxLines: 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_isFixing) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(LuciSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.sentinelFixProgress(
                            _fixStepIndex + 1,
                            _fixStepCount,
                            _stepName(_fixStepId),
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _fixStepCount == 0
                              ? null
                              : (_fixStepIndex + 1) / _fixStepCount,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_checkError != null) ...[
                Card(
                  color: colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(LuciSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.sentinelCheckFailed,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          apiErrorText(context, _checkError!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isChecking ? null : _checkHealth,
                            child: Text(l10n.retry),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Text(
                l10n.sentinelTargetSection,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),

              ..._targets.map((t) {
                Color statusColor;
                IconData statusIcon;
                switch (t.status) {
                  case SentinelStatus.online:
                    statusColor = Colors.green;
                    statusIcon = Icons.check_circle;
                    break;
                  case SentinelStatus.blocked:
                    statusColor = Colors.red;
                    statusIcon = Icons.block;
                    break;
                  case SentinelStatus.timeout:
                    statusColor = Colors.orange;
                    statusIcon = Icons.timer_off;
                    break;
                  default:
                    statusColor = Colors.grey;
                    statusIcon = Icons.help_outline;
                }

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withAlpha(25),
                      child: Icon(statusIcon, color: statusColor, size: 20),
                    ),
                    title: Text(
                      t.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(t.host),
                    trailing: t.latencyMs != null && t.latencyMs! > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${t.latencyMs} ms',
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : Text(
                            _statusName(t.status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                );
              }),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
