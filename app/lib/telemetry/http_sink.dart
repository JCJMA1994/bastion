import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry.dart';

/// Envía registros al servidor por lotes. La cola se guarda en el
/// dispositivo, así que nada se pierde sin conexión ni al cerrar la app.
class HttpTelemetrySink implements TelemetrySink {
  HttpTelemetrySink({
    required this.prefs,
    required this.serverUrl,
    required this.env,
    required this.appVersion,
    http.Client? client,
    this.batchSize = 50,
    this.maxQueue = 1000,
  }) : _client = client ?? http.Client() {
    final raw = prefs.getStringList(_queueKey) ?? const [];
    for (final line in raw) {
      try {
        _queue.add(TelemetryRecord.fromJson(jsonDecode(line) as Map<String, Object?>));
      } on Object {
        continue;
      }
    }
  }

  static const _queueKey = 'bastion.telemetry.queue';
  static const _installKey = 'bastion.telemetry.install';

  final SharedPreferences prefs;
  String serverUrl;
  final String env;
  final String appVersion;
  final http.Client _client;
  final int batchSize;
  final int maxQueue;
  final List<TelemetryRecord> _queue = [];
  Timer? _timer;
  bool _sending = false;

  int get pending => _queue.length;

  /// Identificador aleatorio de la instalación (no identifica a la persona).
  String get installId {
    final existing = prefs.getString(_installKey);
    if (existing != null) return existing;
    final random = math.Random.secure();
    final id = [for (var i = 0; i < 32; i++) random.nextInt(16).toRadixString(16)].join();
    prefs.setString(_installKey, id);
    return id;
  }

  /// Envía periódicamente cada [interval].
  void start(Duration interval) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => flush());
  }

  void stop() => _timer?.cancel();

  @override
  void add(TelemetryRecord record) {
    _queue.add(record);
    if (_queue.length > maxQueue) _queue.removeRange(0, _queue.length - maxQueue);
    _persist();
    if (_queue.length >= batchSize) unawaited(flush());
  }

  @override
  Future<void> flush() async {
    if (_sending || _queue.isEmpty) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(batchSize).toList();
        final uri = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/')
            .resolve('telemetry');
        final response = await _client
            .post(uri,
                headers: {'content-type': 'application/json'},
                body: jsonEncode({
                  'install': installId,
                  'env': env,
                  'version': appVersion,
                  'entries': [for (final r in batch) r.toJson()],
                }))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 429 || response.statusCode >= 500) break;
        // 2xx o error de validación (4xx): el lote no se reintenta.
        _queue.removeRange(0, batch.length);
        _persist();
      }
    } on Object {
      // Sin conexión: se reintenta en el siguiente ciclo.
    } finally {
      _sending = false;
    }
  }

  /// Vacía la cola (al retirar el consentimiento).
  void discard() {
    _queue.clear();
    _persist();
  }

  void _persist() => prefs.setStringList(
      _queueKey, [for (final r in _queue) jsonEncode(r.toJson())]);
}
