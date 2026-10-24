import 'package:luci_mobile/services/interfaces/api_service_interface.dart';

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
    final result = await api.systemExec(
      ip,
      token,
      useHttps,
      command: '/bin/sh',
      params: ['-c', script],
    );
    if (result is! List ||
        result.length < 2 ||
        result[0] != 0 ||
        result[1] is! Map ||
        result[1]['code'] != 0) {
      throw StateError('Не удалось прочитать датчики через file.exec');
    }
    return parse((result[1]['stdout'] ?? '').toString());
  }
}
