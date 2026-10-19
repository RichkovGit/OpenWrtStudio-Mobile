import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/forkop_topology.dart';
import 'package:luci_mobile/widgets/forkop_quick_choices.dart';

void main() {
  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'VPN choices show actual policies and use raw tags at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final f =
            jsonDecode(
                  File('test/fixtures/vpn_topology.json').readAsStringSync(),
                )
                as Map;
        final nodes = ForkopTopology.quickChoices(
          ForkopTopology.parse(
            proxies: f['proxies'] as Map,
            config: f['config'] as Map,
            caches: (f['cache'] as List).cast<Map<String, dynamic>>(),
          ),
        );
        final selections = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ForkopQuickChoices(nodes: nodes, onSelect: selections.add),
            ),
          ),
        );
        expect(find.text('Авто Hella (Запасной 3)'), findsOneWidget);
        expect(find.text('direct-out'), findsNothing);
        expect(find.text('bypass-out'), findsNothing);
        final chosen = tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((c) => c.selected)
            .toList();
        expect(
          chosen
              .where((c) => c.key == const ValueKey('vpn-priority-route'))
              .length,
          1,
        );
        expect(
          chosen.where((c) => c.key == const ValueKey('vpn-auto-shrimp')),
          isEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('vpn-auto-hella')));
        await tester.pump();
        expect(selections, ['auto-hella']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ForkopQuickChoices(
                nodes: nodes,
                busy: true,
                onSelect: selections.add,
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('vpn-auto-blanc')));
        await tester.pump();
        expect(selections, ['auto-hella']);
      },
    );
  }
}
