import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';

/// Reads the same log sources and ACL-limited endpoints as LuCI's log views.
class RouterLogsService {
  const RouterLogsService(this.api);
  final IApiService api;

  static const _facilities = [
    'kern',
    'user',
    'mail',
    'daemon',
    'auth',
    'syslog',
    'lpr',
    'news',
    'uucp',
    'cron',
    'authpriv',
    'ftp',
    'ntp',
    'security',
    'console',
    'cron',
    'local0',
    'local1',
    'local2',
    'local3',
    'local4',
    'local5',
    'local6',
    'local7',
  ];
  static const _levels = [
    'emerg',
    'alert',
    'crit',
    'err',
    'warn',
    'notice',
    'info',
    'debug',
  ];

  Future<String> read(
    RouterSession session, {
    required bool kernel,
    int lines = 200,
  }) async {
    final limit = lines.clamp(1, 1000).toInt();
    if (!kernel) {
      try {
        final raw = validateRpcResult(
          await api.call(
            session.ipAddress,
            session.sysauth,
            session.useHttps,
            object: 'log',
            method: 'read',
            params: {'lines': limit, 'stream': false, 'oneshot': true},
          ),
          object: 'log',
          method: 'read',
        );
        if (raw.length != 2 || raw[1] is! Map || raw[1]['log'] is! List) {
          throw const RpcException(
            object: 'log',
            method: 'read',
            detail: 'invalid response',
          );
        }
        final output = <String>[];
        for (final row in raw[1]['log'] as List) {
          if (row is! Map ||
              row['msg'] is! String ||
              row['time'] is! int ||
              row['priority'] is! int ||
              row['time'] < 0 ||
              row['time'] > 8640000000000000 ||
              row['priority'] < 0 ||
              row['priority'] > 191) {
            throw const RpcException(
              object: 'log',
              method: 'read',
              detail: 'invalid response',
            );
          }
          final stamp = DateTime.fromMillisecondsSinceEpoch(
            row['time'] as int,
            isUtc: true,
          ).toIso8601String();
          final priority = row['priority'] as int;
          output.add(
            '$stamp ${_facilities[priority ~/ 8]}.${_levels[priority % 8]} ${row['msg']}',
          );
        }
        return tail(output.join('\n'), limit);
      } on RpcException catch (error) {
        if (!error.isAccessDenied &&
            !error.isUnavailable &&
            error.detail != 'invalid response') {
          rethrow;
        }
        // Older LuCI grants CGI log reads but not ubus log.read or file.exec.
      }
    }
    final text = await api.readLogDirect(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      kernel: kernel,
    );
    return tail(text, limit);
  }

  static String tail(String text, int lines) {
    final parts = text.replaceAll('\r\n', '\n').split('\n');
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    return parts
        .skip(parts.length > lines ? parts.length - lines : 0)
        .join('\n');
  }
}
