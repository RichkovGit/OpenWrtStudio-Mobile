import 'package:flutter/foundation.dart';

import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/services/router_logs_service.dart';

/// A network tool the router can run on the user's behalf.
enum DiagnosticTool {
  ping('/bin/ping'),
  traceroute('/usr/bin/traceroute'),
  nslookup('/usr/bin/nslookup');

  const DiagnosticTool(this.path);

  /// Absolute path, because rpcd's `file.exec` resolves nothing.
  final String path;
}

@immutable
class DiagnosticResult {
  const DiagnosticResult({
    required this.output,
    required this.exitCode,
    this.stderr,
  });

  final String output;
  final int exitCode;
  final String? stderr;

  bool get succeeded => exitCode == 0;
}

/// Runs the router's own network tools and reads its logs.
class DiagnosticsService {
  const DiagnosticsService(this._api);

  final IApiService _api;

  /// Arguments for [tool] against [target].
  ///
  /// Counts and deadlines are bounded on purpose: `file.exec` is synchronous
  /// and rpcd times it out, so an unbounded `ping` would hang the call and
  /// return nothing at all.
  static List<String> argsFor(DiagnosticTool tool, String target) =>
      switch (tool) {
        DiagnosticTool.ping => ['-c', '5', '-W', '2', target],
        DiagnosticTool.traceroute => [
          '-n',
          '-w',
          '1',
          '-q',
          '1',
          '-m',
          '15',
          target,
        ],
        DiagnosticTool.nslookup => [target],
      };

  Future<DiagnosticResult> run(
    RouterSession session,
    DiagnosticTool tool,
    String target,
  ) async {
    return _exec(session, tool.path, argsFor(tool, target));
  }

  /// Reads the kernel ring buffer through LuCI's fixed log endpoint.
  Future<String> kernelLog(RouterSession session) =>
      RouterLogsService(_api).read(session, kernel: true, lines: 1000);

  /// Reads syslog; an empty journal is never replaced with a different source.
  Future<String> systemLog(RouterSession session, {int lines = 200}) =>
      RouterLogsService(_api).read(session, kernel: false, lines: lines);

  /// Runs [command] and returns whatever it printed, whatever it exited with.
  ///
  /// Deliberately not `systemExec`, which throws on a non-zero exit: here a
  /// non-zero exit *is* the result. `ping` exits 1 for "100% packet loss"
  /// and `nslookup` for NXDOMAIN, and that output is exactly what the user
  /// ran the tool to see.
  Future<DiagnosticResult> _exec(
    RouterSession session,
    String command,
    List<String> params,
  ) async {
    final raw = validateRpcResult(
      await _api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': command, 'params': params},
      ),
      object: 'file',
      method: 'exec',
    );
    // `call` has already turned a non-zero ubus status into an RpcException
    // with whatever detail the router sent; only the shape is checked here.
    if (raw is! List || raw.isEmpty) {
      throw const RpcException(
        object: 'file',
        method: 'exec',
        detail: 'invalid response',
      );
    }
    return _parseExec(raw);
  }

  static DiagnosticResult _parseExec(List<dynamic> raw) {
    // The envelope shape varies between rpcd builds; parse defensively.
    if (raw.length < 2 || raw[1] is! Map) {
      return const DiagnosticResult(output: '', exitCode: -1);
    }
    final data = raw[1] as Map;
    final code = data['code'];
    return DiagnosticResult(
      output: data['stdout']?.toString() ?? '',
      // Unknown, not zero: a body carrying no exit status is a run we
      // cannot vouch for, and calling it a success turns "the log could
      // not be read" into "the log is empty".
      exitCode: code is num ? code.toInt() : -1,
      stderr: data['stderr']?.toString(),
    );
  }
}

/// One parsed syslog line.
@immutable
class LogEntry {
  const LogEntry({
    required this.raw,
    this.timestamp,
    this.facility,
    this.level,
    this.message,
  });

  final String raw;
  final String? timestamp;
  final String? facility;
  final String? level;
  final String? message;

  /// True for anything the user would want to notice.
  bool get isProblem {
    final l = level?.toLowerCase();
    return l == 'err' || l == 'crit' || l == 'alert' || l == 'emerg';
  }

  bool get isWarning => level?.toLowerCase() == 'warn';

  /// Parses `Sun Sep 20 08:53:53 2026 daemon.notice netifd: ...`.
  ///
  /// Anything that does not match is kept verbatim rather than dropped: a log
  /// viewer that silently hides lines it cannot parse is worse than useless
  /// when you are chasing a problem.
  static LogEntry parse(String line) {
    final match =
        RegExp(
          r'^(\w{3}\s+\w{3}\s+\d+\s+[\d:]+\s+\d{4})\s+(\w+)\.(\w+)\s+(.*)$',
        ).firstMatch(line) ??
        RegExp(
          r'^(\d{4}-\d{2}-\d{2}T\S+)\s+(\w+)\.(\w+)\s+(.*)$',
        ).firstMatch(line);
    if (match == null) return LogEntry(raw: line, message: line);
    return LogEntry(
      raw: line,
      timestamp: match.group(1),
      facility: match.group(2),
      level: match.group(3),
      message: match.group(4),
    );
  }

  static List<LogEntry> parseAll(String output) => [
    for (final line in output.split('\n'))
      if (line.trim().isNotEmpty) parse(line),
  ];
}
