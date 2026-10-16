import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

/// Un registro: log, error o evento de analítica.
class TelemetryRecord {
  TelemetryRecord({
    required this.kind,
    required this.name,
    this.level,
    this.message,
    this.data = const {},
    DateTime? time,
  }) : time = (time ?? DateTime.now()).toUtc();

  factory TelemetryRecord.fromJson(Map<String, Object?> json) => TelemetryRecord(
        kind: json['kind']! as String,
        name: json['name']! as String,
        level: json['level'] == null
            ? null
            : LogLevel.values.byName(json['level']! as String),
        message: json['message'] as String?,
        data: (json['data'] as Map<String, Object?>?) ?? const {},
        time: DateTime.parse(json['time']! as String),
      );

  /// log, error o event.
  final String kind;
  final String name;
  final LogLevel? level;
  final String? message;
  final Map<String, Object?> data;
  final DateTime time;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'name': name,
        'time': time.toIso8601String(),
        if (level != null) 'level': level!.name,
        if (message != null) 'message': message,
        if (data.isNotEmpty) 'data': data,
      };

  @override
  String toString() {
    final head = '${time.toIso8601String().substring(11, 19)} '
        '${(level?.name ?? kind).toUpperCase().padRight(7)} $name';
    return [head, message, if (data.isNotEmpty) '$data']
        .whereType<String>()
        .join(' · ');
  }
}

/// Destino de los registros.
abstract interface class TelemetrySink {
  void add(TelemetryRecord record);
  Future<void> flush();
}

/// Últimos registros en memoria, para el visor de la app. Nunca sale del
/// dispositivo.
class MemorySink extends ChangeNotifier implements TelemetrySink {
  MemorySink({this.capacity = 500});

  final int capacity;
  final Queue<TelemetryRecord> _records = Queue();

  List<TelemetryRecord> get records => _records.toList().reversed.toList();

  @override
  void add(TelemetryRecord record) {
    _records.addLast(record);
    if (_records.length > capacity) _records.removeFirst();
    notifyListeners();
  }

  @override
  Future<void> flush() async {}

  void clear() {
    _records.clear();
    notifyListeners();
  }
}

/// Fachada de logs, errores y analítica. Por defecto no envía nada fuera del
/// dispositivo; los envíos remotos dependen del consentimiento del jugador.
class Telemetry {
  Telemetry({
    this.local,
    this.remote,
    this.minLevel = LogLevel.info,
    this.diagnosticsConsent = false,
    this.analyticsConsent = false,
  });

  /// Instancia global. Sin configurar (tests) no hace nada.
  static Telemetry instance = Telemetry();

  final MemorySink? local;
  final TelemetrySink? remote;

  /// Nivel mínimo que se registra (lo ajusta la configuración remota).
  LogLevel minLevel;

  /// Logs y errores al servidor.
  bool diagnosticsConsent;

  /// Eventos de uso al servidor.
  bool analyticsConsent;

  void log(LogLevel level, String name, String message,
      {Map<String, Object?> data = const {}}) {
    if (level.index < minLevel.index) return;
    final record = TelemetryRecord(
        kind: 'log', name: name, level: level, message: message, data: data);
    if (kDebugMode) debugPrint('[bastion] $record');
    local?.add(record);
    if (diagnosticsConsent) remote?.add(record);
  }

  void debug(String name, String message, {Map<String, Object?> data = const {}}) =>
      log(LogLevel.debug, name, message, data: data);
  void info(String name, String message, {Map<String, Object?> data = const {}}) =>
      log(LogLevel.info, name, message, data: data);
  void warning(String name, String message, {Map<String, Object?> data = const {}}) =>
      log(LogLevel.warning, name, message, data: data);

  void error(Object error, StackTrace? stack,
      {String name = 'error', Map<String, Object?> data = const {}}) {
    final record = TelemetryRecord(
      kind: 'error',
      name: name,
      level: LogLevel.error,
      message: '$error\n${_trim(stack)}',
      data: data,
    );
    if (kDebugMode) debugPrint('[bastion] $record');
    local?.add(record);
    if (diagnosticsConsent) remote?.add(record);
  }

  /// Evento de analítica: nombre en snake_case y parámetros simples.
  void event(String name, [Map<String, Object?> params = const {}]) {
    final record = TelemetryRecord(kind: 'event', name: name, data: params);
    local?.add(record);
    if (analyticsConsent) remote?.add(record);
  }

  void screen(String name) => event('screen_view', {'screen': name});

  Future<void> flush() async => remote?.flush();

  /// Las 15 primeras líneas de la pila bastan para localizar un fallo.
  static String _trim(StackTrace? stack) =>
      (stack?.toString() ?? '').split('\n').take(15).join('\n');
}
