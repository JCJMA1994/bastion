import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'admin_page.dart';
import 'match_service.dart';
import 'remote_config_store.dart';
import 'telemetry_store.dart';

/// API HTTP:
///
/// - `POST /matches` `{map, mission, roster}` → `{code, token, side}`
/// - `POST /matches/<code>/join` `{roster}` → `{code, token, side}`
/// - `POST /matches/<code>/deployment` `{centers}` → `{status}`
/// - `GET /matches/<code>?since=n` (Authorization: Bearer token) → estado
/// - `POST /matches/<code>/commands` `{version, command}` → `{version}`
/// - `GET /health`
/// - `GET /config/<env>` → `{values, version}` (304 con If-None-Match)
/// - `POST /telemetry` `{install, env, version, entries}` → `{accepted}`
/// - `GET /admin` (panel), `GET /admin/logs`, `GET /admin/summary`
///   (Authorization: Bearer token de administración)
final class HttpApi {
  HttpApi(
    this.service, {
    this.telemetry,
    this.config,
    this.adminToken,
    this.telemetryPerMinute = 30,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MatchService service;
  final TelemetryStore? telemetry;
  final RemoteConfigStore? config;

  /// Sin token no se puede acceder a los endpoints de administración.
  final String? adminToken;

  /// Envíos de telemetría permitidos por instalación y minuto.
  final int telemetryPerMinute;
  final DateTime Function() _clock;
  final Map<String, (DateTime, int)> _rate = {};

  static const _maxBatch = 200;

  Handler get handler {
    final router = Router()
      ..get('/health', (Request _) => _json({'ok': true}))
      ..post('/matches', (Request r) => _guard(() async {
            final body = await _body(r);
            return service.create(
              mapId: (body['map'] as String?) ?? 'molino',
              missionId: (body['mission'] as String?) ?? 'dominio',
              roster: body['roster'],
            );
          }))
      ..post('/matches/<code>/join', (Request r, String code) => _guard(() async {
            final body = await _body(r);
            return service.join(code, roster: body['roster']);
          }))
      ..post('/matches/<code>/deployment', (Request r, String code) =>
          _guard(() async {
            final body = await _body(r);
            return service.deploy(code, _token(r), centers: body['centers']);
          }))
      ..get('/matches/<code>', (Request r, String code) => _guard(() async {
            final since = int.tryParse(r.url.queryParameters['since'] ?? '') ?? 0;
            return service.view(code, _token(r), since: since);
          }))
      ..post('/matches/<code>/commands', (Request r, String code) =>
          _guard(() async {
            final body = await _body(r);
            return service.submit(code, _token(r),
                version: body['version'], command: body['command']);
          }))
      ..get('/config/<env>', _config)
      ..post('/telemetry', (Request r) => _guard(() async => _telemetry(await _body(r))))
      ..get('/admin', (Request _) => Response.ok(adminPageHtml,
          headers: {'content-type': 'text/html; charset=utf-8'}))
      ..get('/admin/logs', (Request r) => _guard(() async {
            _requireAdmin(r);
            final q = r.url.queryParameters;
            final store = telemetry ?? (throw const MatchError(404, 'telemetry'));
            final hours = int.tryParse(q['hours'] ?? '');
            return {
              'entries': [
                for (final e in store.query(
                  kind: _blank(q['kind']),
                  level: _blank(q['level']),
                  env: _blank(q['env']),
                  text: _blank(q['q']),
                  installId: _blank(q['install']),
                  since: hours == null
                      ? null
                      : _clock().toUtc().subtract(Duration(hours: hours)),
                  limit: (int.tryParse(q['limit'] ?? '') ?? 200).clamp(1, 1000),
                ))
                  e.toJson(),
              ],
            };
          }))
      ..get('/admin/summary', (Request r) => _guard(() async {
            _requireAdmin(r);
            final store = telemetry ?? (throw const MatchError(404, 'telemetry'));
            final hours = int.tryParse(r.url.queryParameters['hours'] ?? '') ?? 24;
            return {
              ...store.summary(
                  since: _clock().toUtc().subtract(Duration(hours: hours))),
              'matches': service.matchCount,
            };
          }));
    return const Pipeline().addMiddleware(_cors()).addHandler(router.call);
  }

  Response _config(Request r, String env) {
    final store = config;
    final found = store?.read(env);
    if (found == null) {
      return _json({'error': 'config'}, status: 404);
    }
    final (values, etag) = found;
    if (r.headers['if-none-match'] == etag) {
      return Response.notModified(headers: {'etag': etag});
    }
    return Response.ok(jsonEncode({'values': values, 'version': etag}), headers: {
      'content-type': 'application/json; charset=utf-8',
      'etag': etag,
      'cache-control': 'no-cache',
    });
  }

  Map<String, Object?> _telemetry(Map<String, Object?> body) {
    final store = telemetry ?? (throw const MatchError(404, 'telemetry'));
    final install = body['install'];
    final env = body['env'];
    final version = body['version'];
    final entries = body['entries'];
    if (install is! String || install.length < 8 || install.length > 64 ||
        env is! String || version is! String || entries is! List<Object?>) {
      throw const MatchError(400, 'telemetry');
    }
    if (entries.length > _maxBatch) throw const MatchError(413, 'batch');
    if (!_allow(install)) throw const MatchError(429, 'rate');
    final parsed = [
      for (final e in entries)
        TelemetryEntry.tryParse(e, installId: install, env: env, appVersion: version),
    ].whereType<TelemetryEntry>().toList();
    store.addAll(parsed);
    return {'accepted': parsed.length};
  }

  /// Ventana fija de un minuto por instalación.
  bool _allow(String key) {
    final now = _clock();
    final (start, count) = _rate[key] ?? (now, 0);
    if (now.difference(start) >= const Duration(minutes: 1)) {
      _rate[key] = (now, 1);
      return true;
    }
    if (count >= telemetryPerMinute) return false;
    _rate[key] = (start, count + 1);
    return true;
  }

  void _requireAdmin(Request r) {
    final expected = adminToken;
    if (expected == null || expected.isEmpty || _token(r) != expected) {
      throw const MatchError(401, 'admin');
    }
  }

  static String? _blank(String? v) => v == null || v.isEmpty ? null : v;

  static String? _token(Request r) {
    final header = r.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring(7);
  }

  static Future<Map<String, Object?>> _body(Request r) async {
    try {
      final decoded = jsonDecode(await r.readAsString());
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // cae al error de abajo
    }
    throw const MatchError(400, 'json');
  }

  static Future<Response> _guard(
      Future<Map<String, Object?>> Function() action) async {
    try {
      return _json(await action());
    } on MatchError catch (e) {
      return _json({'error': e.code}, status: e.status);
    }
  }

  static Response _json(Map<String, Object?> body, {int status = 200}) =>
      Response(status,
          body: jsonEncode(body),
          headers: {'content-type': 'application/json; charset=utf-8'});

  static Middleware _cors() => (inner) => (request) async {
        const headers = {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-allow-methods': 'GET, POST, OPTIONS',
        };
        if (request.method == 'OPTIONS') return Response.ok('', headers: headers);
        final response = await inner(request);
        return response.change(headers: headers);
      };
}
