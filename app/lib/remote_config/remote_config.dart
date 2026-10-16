import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/env.dart';
import '../telemetry/telemetry.dart';

/// Configuración remota: valores por defecto incluidos en la app
/// (`assets/config/defaults.json`), sobrescritos por los últimos recibidos
/// del servidor (`GET /config/<entorno>`) y guardados para el siguiente
/// arranque sin conexión.
class RemoteConfig extends ChangeNotifier {
  RemoteConfig({
    required Map<String, Object?> defaults,
    SharedPreferences? prefs,
    http.Client? client,
    this.env = Env.name,
  })  : _defaults = defaults,
        _prefs = prefs,
        _client = client {
    final cached = prefs?.getString(_valuesKey);
    if (cached != null) {
      try {
        _values = jsonDecode(cached) as Map<String, Object?>;
        _etag = prefs?.getString(_etagKey);
      } on FormatException {
        _values = const {};
      }
    }
  }

  /// Valores por defecto del asset y caché del dispositivo.
  static Future<RemoteConfig> load({AssetBundle? bundle, http.Client? client}) async {
    final raw = await (bundle ?? rootBundle).loadString('assets/config/defaults.json');
    return RemoteConfig(
      defaults: jsonDecode(raw) as Map<String, Object?>,
      prefs: await SharedPreferences.getInstance(),
      client: client,
    );
  }

  static const _valuesKey = 'bastion.remoteConfig.values';
  static const _etagKey = 'bastion.remoteConfig.etag';

  final Map<String, Object?> _defaults;
  final SharedPreferences? _prefs;
  final http.Client? _client;
  final String env;
  Map<String, Object?> _values = const {};
  String? _etag;
  DateTime? lastFetch;

  /// Pide la configuración al servidor. Si falla, se queda con la que tenía.
  Future<void> refresh(String serverUrl) async {
    final client = _client ?? http.Client();
    try {
      final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
      final response = await client.get(base.resolve('config/$env'), headers: {
        if (_etag != null) 'if-none-match': _etag!,
      }).timeout(const Duration(seconds: 8));
      lastFetch = DateTime.now();
      if (response.statusCode == 304) return;
      if (response.statusCode != 200) {
        Telemetry.instance.warning('remote_config',
            'Respuesta ${response.statusCode} al pedir la configuración');
        return;
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      _values = (body['values'] as Map<String, Object?>?) ?? const {};
      _etag = response.headers['etag'];
      await _prefs?.setString(_valuesKey, jsonEncode(_values));
      if (_etag != null) await _prefs?.setString(_etagKey, _etag!);
      Telemetry.instance.info('remote_config', 'Configuración actualizada',
          data: {'version': _etag});
      notifyListeners();
    } on Object catch (e) {
      Telemetry.instance.warning('remote_config', 'Sin configuración remota: $e');
    } finally {
      if (_client == null) client.close();
    }
  }

  Object? operator [](String key) => _values[key] ?? _defaults[key];

  bool getBool(String key, {bool fallback = false}) {
    final v = this[key];
    return v is bool ? v : fallback;
  }

  int getInt(String key, {int fallback = 0}) {
    final v = this[key];
    return v is num ? v.toInt() : fallback;
  }

  String getString(String key, {String fallback = ''}) {
    final v = this[key];
    return v is String ? v : fallback;
  }

  // ------------------------------------------------- valores con nombre

  bool get multiplayerEnabled => getBool('multiplayer_enabled', fallback: true);
  bool get quickBattleEnabled => getBool('quick_battle_enabled', fallback: true);
  bool get aiUseOrders => getBool('ai_use_orders', fallback: true);
  Duration get pollInterval =>
      Duration(seconds: getInt('poll_seconds', fallback: 2).clamp(1, 60));
  Duration get telemetryFlushInterval =>
      Duration(seconds: getInt('telemetry_flush_seconds', fallback: 30).clamp(5, 3600));
  int get campaignStartingRequisas =>
      getInt('campaign_starting_requisas', fallback: 60).clamp(0, 500);
  String get maintenanceMessage => getString('maintenance_message');

  /// Estilo gráfico por defecto: "vector" o "sprites".
  String get artStyle => getString('art_style', fallback: 'vector');
  String get minAppVersion => getString('min_app_version', fallback: '0.0.0');

  LogLevel get logLevel =>
      LogLevel.values.where((l) => l.name == getString('log_level')).firstOrNull ??
      LogLevel.info;

  /// La versión instalada es más antigua que la mínima exigida.
  bool get updateRequired => compareVersions(Env.appVersion, minAppVersion) < 0;
}
