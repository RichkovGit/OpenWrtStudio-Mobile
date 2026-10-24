import 'package:flutter/services.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';

class ProtocolInstallResult {
  final bool success;
  final String message;
  const ProtocolInstallResult(this.success, this.message);
}

class ProtocolInstaller {
  final IApiService api;
  final Duration pollInterval;
  final int maxPolls;
  ProtocolInstaller(this.api, {
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 150,
  });

  static String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  static Map<dynamic, dynamic> _data(dynamic response) {
    if (response is! List || response.length < 2 || response[0] != 0 ||
        response[1] is! Map || response[1]['code'] != 0) {
      throw StateError('file.exec не подтвердил выполнение команды');
    }
    return response[1] as Map;
  }

  Future<ProtocolInstallResult> install({
    required String routerIp,
    required String sysauth,
    required bool useHttps,
    required List<List<String>> groups,
  }) async {
    if (groups.isEmpty || groups.any((g) => g.isEmpty || g.any(
      (p) => !RegExp(r'^[a-zA-Z0-9_.+\-]+$').hasMatch(p)))) {
      return const ProtocolInstallResult(false, 'Некорректный список пакетов');
    }
    String? job;
    Future<String> exec(String script) async {
      final response = await api.systemExec(routerIp, sysauth, useHttps,
        command: '/bin/sh', params: ['-c', script]);
      return (_data(response)['stdout'] ?? '').toString();
    }
    try {
      final source = await rootBundle.loadString('assets/router/install_packages.sh');
      final arguments = groups.map((g) => quote(g.join(' '))).join(' ');
      // rpcd file.exec is short-lived. Close inherited pipes and poll an owned
      // temporary job instead of keeping a package-manager RPC open for minutes.
      final submission = await exec('''
umask 077
job=\$(mktemp -d /tmp/openwrt-studio-install.XXXXXX) || exit 1
printf '%s' ${quote(source)} > "\$job/install.sh" || exit 1
(sh "\$job/install.sh" $arguments > "\$job/output" 2>&1; code=\$?; printf '%s\\n' "\$code" > "\$job/code.tmp"; mv "\$job/code.tmp" "\$job/code") </dev/null >/dev/null 2>&1 &
printf 'OWS_JOB=%s\\n' "\$job"
''');
      final match = RegExp(r'^OWS_JOB=(/tmp/openwrt-studio-install\.[a-zA-Z0-9]+)$', multiLine: true).firstMatch(submission.trim());
      if (match == null) throw StateError('Роутер не подтвердил запуск установки');
      job = match.group(1)!;
      final path = quote(job);
      for (var attempt = 0; attempt < maxPolls; attempt++) {
        if (attempt > 0) await Future<void>.delayed(pollInterval);
        final output = await exec('''
if [ -f $path/code ]; then printf '__OWS_DONE__='; cat $path/code
else printf '__OWS_RUNNING__\\n'; fi
tail -c 8192 $path/output 2>/dev/null
exit 0
''');
        final done = RegExp(r'^__OWS_DONE__=(\d+)\r?$', multiLine: true).firstMatch(output);
        if (done != null) {
          final ok = done.group(1) == '0';
          final details = output.substring(done.end).trim();
          try { await exec('rm -rf $path'); } catch (_) { /* Result is already confirmed. */ }
          return ProtocolInstallResult(ok, ok ? 'Пакеты на роутере установлены и проверены. Для подключения настройте профиль VPN или подписку.' : 'Установка завершилась с кодом ${done.group(1)}.\n$details');
        }
        if (!output.startsWith('__OWS_RUNNING__')) {
          throw StateError('Потерян статус фоновой установки');
        }
      }
      return ProtocolInstallResult(false, 'Установка ещё не подтверждена и может продолжаться. Не запускайте её повторно. Лог: $job/output');
    } catch (error) {
      final status = job == null ? '' : '\nУстановка может продолжаться. Лог: $job/output';
      return ProtocolInstallResult(false, 'Не удалось выполнить установку: $error$status');
    }
  }
}
