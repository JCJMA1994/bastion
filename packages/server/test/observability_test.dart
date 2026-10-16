import 'dart:convert';
import 'dart:io';

import 'package:bastion_server/bastion_server.dart';
import 'package:rules_engine/rules_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String file) =>
    jsonDecode(File('../../data/$file').readAsStringSync())
        as Map<String, Object?>;

void main() {
  late Directory tmp;
  late TelemetryStore telemetry;
  late Handler handler;
  var now = DateTime.utc(2026, 10, 15, 12);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bastion_obs');
    Directory('${tmp.path}/config').createSync();
    File('${tmp.path}/config/prod.json')
        .writeAsStringSync('{"multiplayer_enabled": false, "poll_seconds": 3}');
    telemetry = TelemetryStore(directory: Directory('${tmp.path}/telemetria'));
    now = DateTime.utc(2026, 10, 15, 12);
    handler = HttpApi(
      MatchService(
        catalog: ProfileCatalog.fromJson(_json('units.json')),
        maps: MapTemplate.catalogFromJson(_json('maps.json')),
      ),
      telemetry: telemetry,
      config: RemoteConfigStore(Directory('${tmp.path}/config')),
      adminToken: 'token-de-admin-largo',
      telemetryPerMinute: 2,
      clock: () => now,
    ).handler;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(int, Map<String, Object?>?, Map<String, String>)> call(
      String method, String path,
      {Object? body, Map<String, String> headers = const {}}) async {
    final r = await handler(Request(method, Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body), headers: headers));
    final text = await r.readAsString();
    return (
      r.statusCode,
      text.isEmpty || !text.startsWith('{')
          ? null
          : jsonDecode(text) as Map<String, Object?>,
      r.headers
    );
  }

  Map<String, Object?> batch(List<Object?> entries) => {
        'install': 'instalacion-1234',
        'env': 'prod',
        'version': '0.6.0',
        'entries': entries,
      };

  Map<String, Object?> event(String name, [Map<String, Object?>? data]) => {
        'kind': 'event',
        'name': name,
        'time': now.toIso8601String(),
        if (data != null) 'data': data,
      };

  test('la configuración remota usa ETag y responde 304 si no cambió', () async {
    final (status, body, headers) = await call('GET', '/config/prod');
    expect(status, 200);
    expect((body!['values']! as Map)['multiplayer_enabled'], false);
    final (again, _, _) = await call('GET', '/config/prod',
        headers: {'if-none-match': headers['etag']!});
    expect(again, 304);
    final (missing, _, _) = await call('GET', '/config/otro');
    expect(missing, 404);
  });

  test('la telemetría valida, limita y descarta entradas inválidas', () async {
    final (ok, body, _) = await call('POST', '/telemetry', body: batch([
      event('battle_end', {'result': 'victoria', 'profiles': ['lanceros']}),
      {'kind': 'otro', 'name': 'x', 'time': now.toIso8601String()},
      {'kind': 'log', 'level': 'error', 'name': 'red', 'message': 'Sin conexión',
          'time': now.toIso8601String()},
    ]));
    expect(ok, 200);
    expect(body!['accepted'], 2);

    await call('POST', '/telemetry', body: batch([]));
    final (limited, _, _) = await call('POST', '/telemetry', body: batch([]));
    expect(limited, 429);

    now = now.add(const Duration(minutes: 1));
    final (again, _, _) = await call('POST', '/telemetry', body: batch([]));
    expect(again, 200);
  });

  test('el panel de administración exige token y filtra registros', () async {
    await call('POST', '/telemetry', body: batch([
      event('battle_end', {'result': 'victoria', 'profiles': ['lanceros', 'tiradores']}),
      event('battle_end', {'result': 'derrota', 'profiles': ['lanceros']}),
      {'kind': 'error', 'name': 'FlutterError', 'message': 'Boom\nstack',
          'time': now.toIso8601String()},
    ]));

    final (denied, _, _) = await call('GET', '/admin/logs');
    expect(denied, 401);

    const auth = {'authorization': 'Bearer token-de-admin-largo'};
    final (_, logs, _) = await call('GET', '/admin/logs?kind=error', headers: auth);
    expect((logs!['entries']! as List), hasLength(1));

    final (_, summary, _) = await call('GET', '/admin/summary', headers: auth);
    final profiles = summary!['profiles']! as Map<String, Object?>;
    expect((profiles['lanceros']! as Map)['battles'], 2);
    expect((profiles['lanceros']! as Map)['winRate'], 0.5);
    expect((summary['errors']! as List).single, {'name': 'FlutterError: Boom', 'count': 1});

    final (page, _, headers) = await call('GET', '/admin');
    expect(page, 200);
    expect(headers['content-type'], contains('text/html'));
  });

  test('la telemetría se guarda en disco y se recupera', () async {
    await call('POST', '/telemetry', body: batch([event('app_open')]));
    final restored = TelemetryStore(directory: Directory('${tmp.path}/telemetria'))
      ..restore(days: 400);
    expect(restored.query(kind: 'event').single.name, 'app_open');
  });
}
