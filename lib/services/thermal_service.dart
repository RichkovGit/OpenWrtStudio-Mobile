import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/api_service.dart';

class ThermalReading {
  final String path;
  final String label;
  final double? celsius;
  const ThermalReading(this.path, this.label, this.celsius);
}

class ThermalService {
  final IApiService api;
  ThermalService(this.api);

  static const script = r'''
for p in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do
    [ -f "$p" ] || continue
    dir=${p%/*}
    case "$p" in
        */thermal_zone*/temp) label=$(cat "$dir/type" 2>/dev/null);;
        *) stem=${p%_input}; label=$(cat "${stem}_label" 2>/dev/null)
           [ -n "$label" ] || label=$(cat "$dir/name" 2>/dev/null);;
    esac
    [ -n "$label" ] || label=${dir##*/}
    label=$(printf '%s' "$label" | tr '|\r\n' '   ')
    value=$(cat "$p" 2>/dev/null)
    printf '%s|%s|%s\n' "$p" "$label" "$value"
done
exit 0
''';

  static List<ThermalReading> parse(String output) {
    final readings = <String, ThermalReading>{};
    for (final line in output.split('\n')) {
      final fields = line.split('|');
      if (fields.length != 3 || !fields[0].startsWith('/sys/class/')) continue;
      final raw = double.tryParse(fields[2].trim());
      // Both thermal_zone/temp and hwmon/tempN_input use millidegrees.
      final value = raw == null ? null : raw / 1000;
      final valid =
          value != null && value.isFinite && value >= -100 && value <= 200;
      readings[fields[0]] = ThermalReading(
        fields[0],
        fields[1].trim(),
        valid ? value : null,
      );
    }
    return readings.values.toList();
  }

  Future<List<ThermalReading>> read({
    required String ip,
    required String token,
    required bool useHttps,
  }) async {
    dynamic result;
    try {
      result = await api.systemExec(
        ip,
        token,
        useHttps,
        command: '/bin/sh',
        params: ['-c', script],
      );
      result = validateRpcResult(result, object: 'file', method: 'exec');
    } on RpcException catch (error) {
      if (!error.isAccessDenied) rethrow;
      // Reading a sensor does not require a general shell. Respect each
      // file.list/read ACL instead; never grant access or retry a write.
      return _readFiles(ip, token, useHttps);
    }
    if (result is! List ||
        result.length < 2 ||
        result[0] != 0 ||
        result[1] is! Map ||
        result[1]['code'] != 0) {
      throw StateError('Не удалось прочитать датчики через file.exec');
    }
    return parse((result[1]['stdout'] ?? '').toString());
  }

  Future<List<ThermalReading>> _readFiles(
    String ip,
    String token,
    bool useHttps,
  ) async {
    Future<Map> call(String method, String path) async {
      final result = validateRpcResult(
        await api.call(
          ip,
          token,
          useHttps,
          object: 'file',
          method: method,
          params: {'path': path},
        ),
        object: 'file',
        method: method,
      );
      if (result.length != 2 || result[1] is! Map) {
        throw RpcException(
          object: 'file',
          method: method,
          detail: 'invalid response',
        );
      }
      return result[1] as Map;
    }

    Future<List<String>> list(String path) async {
      final entries = (await call('list', path))['entries'];
      if (entries is! List ||
          entries.any((entry) => entry is! Map || entry['name'] is! String)) {
        throw const RpcException(
          object: 'file',
          method: 'list',
          detail: 'invalid response',
        );
      }
      return entries.map((entry) => entry['name'] as String).toList();
    }

    Future<String> read(String path) async {
      final data = (await call('read', path))['data'];
      if (data is! String) {
        throw const RpcException(
          object: 'file',
          method: 'read',
          detail: 'invalid response',
        );
      }
      return data.trim().replaceAll(RegExp(r'[|\r\n]'), ' ');
    }

    final output = <String>[];
    Object? firstError;
    var enumerated = false;
    for (final root in ['/sys/class/thermal', '/sys/class/hwmon']) {
      try {
        final thermal = root.endsWith('/thermal');
        final names = await list(root);
        enumerated = true;
        final directoryPattern = RegExp(
          thermal ? r'^thermal_zone\d+$' : r'^hwmon\d+$',
        );
        for (final name in names.where(directoryPattern.hasMatch).take(64)) {
          final directory = '$root/$name';
          try {
            final inputs = thermal
                ? ['temp']
                : (await list(
                    directory,
                  )).where(RegExp(r'^temp\d+_input$').hasMatch).take(128);
            for (final input in inputs) {
              try {
                final value = await read('$directory/$input');
                var label = name;
                // Driver labels are optional; denied/missing labels must not
                // discard an independently permitted temperature value.
                for (final labelPath
                    in thermal
                        ? ['$directory/type']
                        : [
                            '$directory/${input.replaceFirst('_input', '_label')}',
                            '$directory/name',
                          ]) {
                  try {
                    final text = await read(labelPath);
                    if (text.isNotEmpty) {
                      label = text;
                      break;
                    }
                  } catch (_) {
                    /* Use the directory name. */
                  }
                }
                output.add('$directory/$input|$label|$value');
              } catch (error) {
                firstError ??= error;
              }
            }
          } catch (error) {
            firstError ??= error;
          }
        }
      } catch (error) {
        firstError ??= error;
      }
    }
    if (output.isEmpty && (firstError != null || !enumerated)) {
      throw firstError ?? StateError('Не удалось перечислить датчики');
    }
    return parse(output.join('\n'));
  }
}
