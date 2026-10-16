import 'dart:convert';

import 'package:bastion/core/env.dart';
import 'package:bastion/remote_config/remote_config.dart';
import 'package:bastion/telemetry/http_sink.dart';
import 'package:bastion/telemetry/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ListSink implements TelemetrySink {
  final List<TelemetryRecord> records = [];
  @override
  void add(TelemetryRecord record) => records.add(record);
  @override
  Future<void> flush() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Telemetry', () {
    test('sin consentimiento nada sale del dispositivo', () {
      final local = MemorySink();
      final remote = _ListSink();
      final t = Telemetry(local: local, remote: remote)
        ..event('battle_end', {'result': 'victoria'})
        ..warning('red', 'Sin conexión')
        ..error(StateError('x'), StackTrace.current);
      expect(local.records, hasLength(3));
      expect(remote.records, isEmpty);

      t
        ..analyticsConsent = true
        ..event('app_open');
      expect(remote.records.single.name, 'app_open');

      t
        ..diagnosticsConsent = true
        ..error(StateError('y'), null, name: 'boom');
      expect(remote.records.last.kind, 'error');
    });

    test('el nivel mínimo filtra los logs', () {
      final local = MemorySink();
      Telemetry(local: local, minLevel: LogLevel.warning)
        ..debug('a', 'no')
        ..info('b', 'no')
        ..warning('c', 'sí');
      expect(local.records.single.name, 'c');
    });
  });

  group('HttpTelemetrySink', () {
    test('envía por lotes y vacía la cola', () async {
      final batches = <Map<String, Object?>>[];
      final prefs = await SharedPreferences.getInstance();
      final sink = HttpTelemetrySink(
        prefs: prefs,
        serverUrl: 'http://servidor',
        env: 'qa',
        appVersion: '1.0.0',
        batchSize: 2,
        client: MockClient((request) async {
          batches.add(jsonDecode(request.body) as Map<String, Object?>);
          return http.Response('{"accepted":2}', 200);
        }),
      );
      for (var i = 0; i < 3; i++) {
        sink.add(TelemetryRecord(kind: 'event', name: 'e$i'));
      }
      await sink.flush();
      // El primer lote salió solo al llenarse; se espera a que termine.
      for (var i = 0; i < 10 && sink.pending > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await sink.flush();
      }
      expect(sink.pending, 0);
      expect(batches.expand((b) => b['entries']! as List), hasLength(3));
      expect(batches.first['install'], hasLength(32));
      expect(batches.first['env'], 'qa');
    });

    test('si el servidor falla, la cola se conserva entre arranques', () async {
      final prefs = await SharedPreferences.getInstance();
      HttpTelemetrySink sink(int status) => HttpTelemetrySink(
            prefs: prefs,
            serverUrl: 'http://servidor',
            env: 'prod',
            appVersion: '1.0.0',
            client: MockClient((_) async => http.Response('', status)),
          );
      final first = sink(503)..add(TelemetryRecord(kind: 'log', name: 'x'));
      await first.flush();
      expect(first.pending, 1);

      final second = sink(200);
      expect(second.pending, 1);
      await second.flush();
      expect(second.pending, 0);
    });

    test('al retirar el consentimiento se descarta lo pendiente', () async {
      final sink = HttpTelemetrySink(
        prefs: await SharedPreferences.getInstance(),
        serverUrl: 'http://servidor',
        env: 'prod',
        appVersion: '1.0.0',
        client: MockClient((_) async => http.Response('', 503)),
      )..add(TelemetryRecord(kind: 'event', name: 'x'));
      sink.discard();
      expect(sink.pending, 0);
    });
  });

  group('RemoteConfig', () {
    test('usa los valores por defecto, luego los del servidor y su caché', () async {
      final prefs = await SharedPreferences.getInstance();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/config/prod');
        if (request.headers['if-none-match'] == '"v1"') {
          return http.Response('', 304);
        }
        return http.Response(
            jsonEncode({'values': {'multiplayer_enabled': false, 'poll_seconds': 5}}),
            200,
            headers: {'etag': '"v1"'});
      });
      final config = RemoteConfig(
        defaults: const {'multiplayer_enabled': true, 'poll_seconds': 2},
        prefs: prefs,
        client: client,
        env: 'prod',
      );
      expect(config.multiplayerEnabled, isTrue);

      await config.refresh('http://servidor');
      expect(config.multiplayerEnabled, isFalse);
      expect(config.pollInterval, const Duration(seconds: 5));

      await config.refresh('http://servidor');
      expect(calls, 2);
      expect(config.multiplayerEnabled, isFalse);

      // Otro arranque sin conexión: se usan los valores guardados.
      final offline = RemoteConfig(
        defaults: const {'multiplayer_enabled': true},
        prefs: prefs,
        client: MockClient((_) async => throw Exception('sin red')),
        env: 'prod',
      );
      await offline.refresh('http://servidor');
      expect(offline.multiplayerEnabled, isFalse);
    });

    test('pide actualizar si la versión es más antigua que la mínima', () {
      expect(compareVersions('1.2.0', '1.10.0'), -1);
      expect(compareVersions('2.0.0-dev', '2.0.0'), 0);
      final config = RemoteConfig(defaults: const {'min_app_version': '99.0.0'});
      expect(config.updateRequired, isTrue);
    });
  });
}
