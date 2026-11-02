import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

class _ClientsState extends AppState {
  _ClientsState(this.client)
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final Client client;
  final model.Router router = model.Router(
    id: 'layout',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
  );

  @override
  List<model.Router> get routers => [router];

  @override
  model.Router? get selectedRouter => router;

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async => [client];
}

void main() {
  for (final width in [320.0, 360.0, 600.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final online in [true, false]) {
        testWidgets(
          'collapsed client at $width, scale $scale, online $online',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 1100));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final client = Client(
              hostname:
                  'DESKTOP-LIVING-ROOM-Рабочий-компьютер-с-длинным-именем',
              ipAddress: '192.168.1.138',
              macAddress: '02:00:00:00:00:01',
              connectionType: ConnectionType.wireless,
              wifiBand: '5 GHz',
              signal: -46,
              isOnline: online,
              isBlocked: online,
            );
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  appStateProvider.overrideWith((ref) => _ClientsState(client)),
                ],
                child: MaterialApp(
                  locale: const Locale('ru'),
                  localizationsDelegates: luciLocalizationsDelegates,
                  supportedLocales: const [Locale('ru')],
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: const ClientsScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();

            // The full name must actually paint without ellipsis or clipping,
            // rather than merely exist in the Text widget's backing string.
            final name = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(client.hostname),
                matching: find.byType(RichText),
              ),
            );
            expect(name.maxLines, isNull);
            expect(name.didExceedMaxLines, isFalse);
            final nameBoxes = name.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: client.hostname.length,
              ),
            );
            expect(nameBoxes, isNotEmpty);
            for (final box in nameBoxes) {
              expect(box.left, greaterThanOrEqualTo(-0.1));
              expect(box.right, lessThanOrEqualTo(name.size.width + 0.1));
              expect(box.bottom, lessThanOrEqualTo(name.size.height + 0.1));
            }
            final address = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(client.ipAddress),
                matching: find.byType(RichText),
              ),
            );
            final addressBoxes = address.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: client.ipAddress.length,
              ),
            );
            expect(addressBoxes.map((box) => box.top).toSet(), hasLength(1));
            expect(find.byIcon(Icons.expand_more), findsOneWidget);
            expect(find.byIcon(Icons.expand_less), findsNothing);
            expect(find.text(client.macAddress), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
