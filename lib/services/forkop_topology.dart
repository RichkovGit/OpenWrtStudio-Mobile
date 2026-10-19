import 'dart:convert';
import 'package:luci_mobile/models/forkop_node.dart';

/// Parses the same cache/config/runtime topology as the desktop client.
class ForkopTopology {
  static List<Map<String, dynamic>> documents(String text) {
    final result = <Map<String, dynamic>>[];
    var start = -1, depth = 0;
    var quoted = false, escaped = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (start < 0) {
        if (c.trim().isEmpty) continue;
        if (c != '{') break;
        start = i;
        depth = 1;
        continue;
      }
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
        if (depth == 0) {
          try {
            result.add(
              Map<String, dynamic>.from(
                jsonDecode(text.substring(start, i + 1)) as Map,
              ),
            );
          } on FormatException {
            break;
          }
          start = -1;
        }
      }
    }
    return result;
  }

  static List<ForkopNode> parse({
    Map proxies = const {},
    Map config = const {},
    List<Map<String, dynamic>> caches = const [],
  }) {
    final entries = <String, Map<String, dynamic>>{};
    Map<String, dynamic> get(String tag) => entries.putIfAbsent(
      tag,
      () => {
        'name': tag,
        'label': tag,
        'all': <String>[],
        'live': false,
        'mutable': false,
      },
    );
    List<String> strings(dynamic value) =>
        value is List ? value.whereType<String>().toList() : [];
    void metadata(Map<String, dynamic> e, dynamic value) {
      if (value is! Map) return;
      for (final key in ['displayName', 'label', 'name', 'title']) {
        if (value[key] is String && (value[key] as String).isNotEmpty) {
          e['label'] = value[key];
          break;
        }
      }
      if (value['type'] is String) e['type'] = value['type'];
      if (value['server'] is String) e['server'] = value['server'];
      if (value['server_port'] is num || value['port'] is num) {
        e['port'] = ((value['server_port'] ?? value['port']) as num).toInt();
      }
      for (final key in ['outbounds', 'all', 'members', 'nodes']) {
        if (value[key] is List) {
          e['all'] = strings(value[key]);
          break;
        }
      }
    }

    if (config['outbounds'] is List) {
      for (final item in config['outbounds'] as List) {
        if (item is! Map || item['tag'] is! String) continue;
        final e = get(item['tag'] as String);
        metadata(e, item);
        e['all'] = strings(item['outbounds']);
      }
    }
    final sections = <String>{};
    for (final cache in caches) {
      if (cache['section'] is String) sections.add(cache['section'] as String);
      if (cache['servers'] is Map) {
        (cache['servers'] as Map).forEach((tag, value) {
          final e = get(tag.toString());
          if (value is String) {
            e['server'] = value;
          } else {
            metadata(e, value);
          }
        });
      }
      if (cache['outboundMetadata'] is Map) {
        final columns = cache['outboundMetadata'] as Map;
        for (final pair in {'names': 'label', 'protocols': 'type'}.entries) {
          if (columns[pair.key] is Map) {
            (columns[pair.key] as Map).forEach((tag, value) {
              if (value is String) get(tag.toString())[pair.value] = value;
            });
          }
        }
        columns.forEach((tag, value) {
          if (![
            'names',
            'protocols',
            'countries',
            'transports',
            'securities',
          ].contains(tag)) {
            metadata(get(tag.toString()), value);
          }
        });
      }
      for (final kind in {
        'urltestGroups': 'urltest',
        'priorityGroups': 'priority',
      }.entries) {
        if (cache[kind.key] is! Map) continue;
        (cache[kind.key] as Map).forEach((name, value) {
          final tag = value is Map && value['tag'] is String
              ? value['tag'] as String
              : name.toString();
          final e = get(tag);
          metadata(e, value);
          e['type'] = kind.value;
          if (value is String) e['label'] = value;
          if (value is List) e['all'] = strings(value);
        });
      }
    }
    proxies.forEach((name, value) {
      if (value is! Map) return;
      final e = get(name.toString());
      final type = value['type']?.toString() ?? e['type']?.toString() ?? '';
      if (e['type'] != 'priority' || type.toLowerCase() != 'selector') {
        e['type'] = type;
      }
      e['live'] = true;
      e['mutable'] = type.toLowerCase() == 'selector';
      e['now'] = value['now'];
      if (value['all'] is List) e['all'] = strings(value['all']);
      e['history'] = value['history'];
      e['delay'] = value['delay'];
    });
    bool isGroup(Map e) =>
        (e['all'] as List).isNotEmpty ||
        [
          'selector',
          'urltest',
          'priority',
          'fallback',
          'loadbalance',
          'load-balance',
        ].contains(e['type']?.toString().toLowerCase());
    bool internal(Map e) =>
        [
          'direct',
          'reject',
          'block',
          'dns',
          'pass',
          'compatible',
        ].contains(e['type']?.toString().toLowerCase()) ||
        [
          'GLOBAL',
          'DIRECT',
          'REJECT',
          'direct-out',
          'bypass-out',
          'block-out',
          'dns-out',
        ].contains(e['name']);
    final groups = entries.values
        .where((e) => isGroup(e) && !internal(e))
        .toList();
    final referenced = groups.expand((e) => e['all'] as List<String>).toSet();
    final roots = groups.where((e) => !referenced.contains(e['name'])).toList();
    final route = config['route'];
    final finalTag = route is Map ? route['final'] : null;
    final rootTags = sections
        .map(
          (section) =>
              '$section-out${section == 'direct' || section == 'bypass' ? '-1' : ''}',
        )
        .where(
          (tag) =>
              entries[tag] != null &&
              isGroup(entries[tag]!) &&
              !internal(entries[tag]!),
        )
        .toSet();
    if (rootTags.isEmpty) {
      if (entries[finalTag] != null &&
          isGroup(entries[finalTag]!) &&
          !internal(entries[finalTag]!)) {
        rootTags.add(finalTag as String);
      } else if (entries['main-out'] != null && isGroup(entries['main-out']!)) {
        rootTags.add('main-out');
      } else if (roots.length == 1) {
        rootTags.add(roots.single['name'] as String);
      }
    }
    final active = <String>{};
    for (final root in rootTags) {
      var current = root;
      while (entries[current] != null &&
          entries[current]!['live'] == true &&
          active.add(current)) {
        current = entries[current]!['now']?.toString() ?? '';
      }
    }
    final selectedPolicies = rootTags
        .map((tag) => entries[tag]!['now'])
        .toSet();
    int? latency(Map e, Set<String> seen) {
      if (!seen.add(e['name'] as String)) return null;
      final delay = ForkopNode.latestDelay(e['history'], e['delay']);
      if (delay != null) return delay;
      final next = entries[e['now']];
      return next != null ? latency(next, seen) : null;
    }

    String selector(Map target) {
      final parents = groups
          .where(
            (e) =>
                e['live'] == true &&
                e['mutable'] == true &&
                e['name'] != target['name'] &&
                (e['all'] as List).contains(target['name']),
          )
          .toList();
      final directParents = parents
          .where((e) => rootTags.contains(e['name']))
          .toList();
      if (directParents.length == 1) {
        return directParents.single['name'] as String;
      }
      final onPath = parents.where((e) => active.contains(e['name'])).toList();
      return onPath.length == 1
          ? onPath.single['name'] as String
          : parents.length == 1
          ? parents.single['name'] as String
          : '';
    }

    final result = entries.values
        .where(
          (e) =>
              !internal(e) &&
              (isGroup(e) || e['live'] == true || e['server'] != null),
        )
        .map(
          (e) => ForkopNode.fromJson({
            ...e,
            'isActive': isGroup(e)
                ? selectedPolicies.contains(e['name'])
                : active.contains(e['name']),
            'isOnActivePath': active.contains(e['name']),
            'group': selector(e),
            'delay': latency(e, {}),
            'history': null,
            'hasLiveState': e['live'],
            'canSelectMembers': e['mutable'],
          }),
        )
        .toList();
    result.sort((a, b) {
      final group = (b.isGroup ? 1 : 0) - (a.isGroup ? 1 : 0);
      return group != 0 ? group : a.displayTitle.compareTo(b.displayTitle);
    });
    return result;
  }

  static List<ForkopNode> quickChoices(List<ForkopNode> nodes) {
    final actionable = nodes
        .where((n) => n.group.isNotEmpty && n.hasLiveState)
        .toList();
    final groups = actionable.where((n) => n.isGroup).toList();
    final active = actionable.where((n) => n.isActive && !n.isGroup);
    final choices = groups.isNotEmpty
        ? [...groups, ...active]
        : [
            ...actionable.where((n) => n.isActive),
            ...actionable.where((n) => !n.isActive).take(8),
          ];
    final seen = <String>{};
    return choices.where((n) => seen.add(n.name)).toList();
  }
}
