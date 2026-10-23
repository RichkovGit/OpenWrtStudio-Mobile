import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/router_session.dart';

const _owner = RouterSession(
  routerId: 'original-router',
  ipAddress: '192.0.2.1',
  sysauth: 'test-session',
  useHttps: false,
  token: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('client results keep the session that supplied them', () async {
    final api = _DelayedClients();
    final state = _ClientState(api);
    addTearDown(state.dispose);
    final pending = state.fetchClientsForSelectedRouter();
    api.reply.complete(_leases);
    final clients = await pending;
    expect(clients, hasLength(1));
    expect(clients.single.routerId, _owner.routerId);
  });

  test('client results are discarded after a session change', () async {
    final api = _DelayedClients();
    final state = _ClientState(api);
    addTearDown(state.dispose);
    final pending = state.fetchClientsForSelectedRouter();
    state.owner = null;
    api.reply.complete(_leases);
    expect(await pending, isEmpty);
  });
}

const _leases = [
  0,
  {
    'dhcp_leases': [
      {'macaddr': '02:00:00:00:00:01', 'ipaddr': '192.0.2.2'},
    ],
  },
];

class _ClientState extends AppState {
  _ClientState(_DelayedClients api)
    : super.forTesting(
        apiService: api,
        authService: MockAuthService(),
        reviewerMode: true,
      );

  RouterSession? owner = _owner;
  @override
  RouterSession? get currentSession => owner;
}

class _DelayedClients extends MockApiService {
  final reply = Completer<dynamic>();
  @override
  Future<Map<String, Set<String>>> fetchAssociatedStations() async => {};
  @override
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  ) => reply.future;
}
