import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/router_logs_service.dart';
import 'package:luci_mobile/state/router_session.dart';

typedef Reply = Future<void> Function(HttpRequest request, Map<String, String> form);

Future<(String, List<Map<String, String>>)> serve(Reply reply) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final forms = <Map<String, String>>[];
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    if (request.uri.path.endsWith('/ubus')) {
      final payload = jsonDecode(body) as Map;
      expect(payload['params'][1], 'log');
      expect(payload['params'][2], 'read');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': [6]}));
    } else {
      expect(request.method, 'POST');
      expect(request.uri.path, '/cgi-bin/cgi-exec');
      expect(request.uri.query, isEmpty);
      expect(request.headers.contentType?.mimeType, 'application/x-www-form-urlencoded');
      final form = Uri.splitQueryString(body);
      forms.add(form);
      await reply(request, form);
    }
    await request.response.close();
  });
  return ('127.0.0.1:${server.port}', forms);
}

void main() {
  test('native permission denial falls back to the exact CGI syslog command and form session', () async {
    final (host, forms) = await serve((request, form) async {
      request.response.headers.contentType = ContentType.text;
      request.response.write('Журнал: событие роутера\n');
    });
    final result = await RouterLogsService(RealApiService()).read(
      RouterSession(routerId: 'r', ipAddress: host, sysauth: 'sid & +', useHttps: false, token: 1),
      kernel: false,
    );
    expect(result, 'Журнал: событие роутера');
    expect(forms.single, {'sessionid': 'sid & +', 'command': '/usr/libexec/syslog-wrapper', 'stderr': '0'});
  });

  test('kernel CGI command matches the permitted LuCI -r invocation', () async {
    final (host, forms) = await serve((request, form) async {
      request.response.write('<6>[0.1] kernel\n');
    });
    expect(await RealApiService().readLogDirect(host, 'sid', false, kernel: true), '<6>[0.1] kernel\n');
    expect(forms.single['command'], '/bin/dmesg -r');
  });

  test('older system readers are tried only after missing or denied fixed readers', () async {
    final (host, forms) = await serve((request, form) async {
      if (form['command'] == '/usr/libexec/syslog-wrapper') {
        request.response.statusCode = 404;
      } else {
        request.response.write('older syslog');
      }
    });
    expect(await RealApiService().readLogDirect(host, 'sid', false, kernel: false), 'older syslog');
    expect(forms.map((f) => f['command']), ['/usr/libexec/syslog-wrapper', '/sbin/logread']);
  });

  test('denied CGI is not a successful empty kernel log', () async {
    final (host, forms) = await serve((request, form) async {
      request.response.statusCode = 403;
      request.response.write('Access to command denied by ACL');
    });
    await expectLater(RealApiService().readLogDirect(host, 'sid', false, kernel: true),
      throwsA(isA<RpcException>().having((e) => e.isAccessDenied, 'denied', isTrue)));
    expect(forms, hasLength(1));
  });

  test('redirects are rejected and cannot forward the form session', () async {
    final (host, forms) = await serve((request, form) async {
      request.response.statusCode = 302;
      request.response.headers.set('Location', '/login');
    });
    await expectLater(RealApiService().readLogDirect(host, 'sid', false, kernel: true), throwsA(isA<RpcException>()));
    expect(forms, hasLength(1));
  });

  test('an HTML login page is not displayed as log text', () async {
    final (host, forms) = await serve((request, form) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>Sign in</html>');
    });
    await expectLater(RealApiService().readLogDirect(host, 'sid', false, kernel: true), throwsA(isA<RpcException>()));
    expect(forms, hasLength(1));
  });

  test('a CGI child failure returned inside HTTP 200 is still a read error', () async {
    final (host, forms) = await serve((request, form) async {
      request.response.write('Status: 500 Failed execv(...)\r\nContent-Type: text/plain\r\n\r\nError');
    });
    await expectLater(RealApiService().readLogDirect(host, 'sid', false, kernel: true), throwsStateError);
    expect(forms, hasLength(1));
  });

  test('log responses are bounded instead of buffering unlimited text', () async {
    final (host, forms) = await serve((request, form) async {
      request.response.add(List.filled(4 * 1024 * 1024 + 1, 120));
    });
    await expectLater(RealApiService().readLogDirect(host, 'sid', false, kernel: true), throwsStateError);
    expect(forms, hasLength(1));
  });
}
