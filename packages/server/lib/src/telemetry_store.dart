import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Entrada de telemetría enviada por la app: log, error o evento.
final class TelemetryEntry {
  const TelemetryEntry({
    required this.kind,
    required this.name,
    required this.time,
    required this.installId,
    required this.env,
    required this.appVersion,
    this.level,
    this.message,
    this.data = const {},
  });

  /// Valida una entrada recibida. Devuelve nulo si no es válida.
  static TelemetryEntry? tryParse(Object? json,
      {required String installId, required String env, required String appVersion}) {
    if (json is! Map<String, Object?>) return null;
    final kind = json['kind'];
    final name = json['name'];
    final time = json['time'];
    if (kind is! String || !const {'log', 'error', 'event'}.contains(kind)) return null;
    if (name is! String || name.isEmpty || name.length > 80) return null;
    final parsedTime = time is String ? DateTime.tryParse(time) : null;
    if (parsedTime == null) return null;
    final data = json['data'];
    final message = json['message'];
    return TelemetryEntry(
      kind: kind,
      name: name,
      time: parsedTime.toUtc(),
      installId: installId,
      env: env,
      appVersion: appVersion,
      level: json['level'] is String ? json['level']! as String : null,
      message: message is String
          ? (message.length > 4000 ? message.substring(0, 4000) : message)
          : null,
      data: data is Map<String, Object?> ? _clip(data) : const {},
    );
  }

  /// Limita el tamaño de los datos adjuntos.
  static Map<String, Object?> _clip(Map<String, Object?> data) {
    final out = <String, Object?>{};
    for (final e in data.entries.take(30)) {
      final v = e.value;
      out[e.key] = v is String && v.length > 500 ? v.substring(0, 500) : v;
    }
    return out;
  }

  factory TelemetryEntry.fromJson(Map<String, Object?> json) => TelemetryEntry(
        kind: json['kind']! as String,
        name: json['name']! as String,
        time: DateTime.parse(json['time']! as String),
        installId: json['install']! as String,
        env: json['env']! as String,
        appVersion: json['version']! as String,
        level: json['level'] as String?,
        message: json['message'] as String?,
        data: (json['data'] as Map<String, Object?>?) ?? const {},
      );

  final String kind;
  final String name;
  final DateTime time;
  final String installId;
  final String env;
  final String appVersion;
  final String? level;
  final String? message;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'name': name,
        'time': time.toIso8601String(),
        'install': installId,
        'env': env,
        'version': appVersion,
        if (level != null) 'level': level,
        if (message != null) 'message': message,
        if (data.isNotEmpty) 'data': data,
      };
}

/// Guarda la telemetría: las últimas entradas en memoria para consultarlas
/// rápido y, opcionalmente, todas en archivos JSONL diarios.
final class TelemetryStore {
  TelemetryStore({this.directory, this.memoryLimit = 5000}) {
    directory?.createSync(recursive: true);
  }

  final Directory? directory;
  final int memoryLimit;
  final Queue<TelemetryEntry> _recent = Queue();

  int get length => _recent.length;

  void addAll(Iterable<TelemetryEntry> entries) {
    final byDay = <String, StringBuffer>{};
    for (final e in entries) {
      _recent.addLast(e);
      if (_recent.length > memoryLimit) _recent.removeFirst();
      if (directory != null) {
        final day = e.time.toIso8601String().substring(0, 10);
        (byDay[day] ??= StringBuffer()).writeln(jsonEncode(e.toJson()));
      }
    }
    for (final e in byDay.entries) {
      File('${directory!.path}/telemetria-${e.key}.jsonl')
          .writeAsStringSync(e.value.toString(), mode: FileMode.append);
    }
  }

  /// Recupera las entradas de los últimos [days] días de disco.
  void restore({int days = 2}) {
    final dir = directory;
    if (dir == null) return;
    final now = DateTime.now().toUtc();
    for (var i = days - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i)).toIso8601String().substring(0, 10);
      final file = File('${dir.path}/telemetria-$day.jsonl');
      if (!file.existsSync()) continue;
      for (final line in file.readAsLinesSync()) {
        try {
          _recent.addLast(TelemetryEntry.fromJson(
              jsonDecode(line) as Map<String, Object?>));
          if (_recent.length > memoryLimit) _recent.removeFirst();
        } on Object {
          continue;
        }
      }
    }
  }

  /// Entradas recientes filtradas, de la más nueva a la más antigua.
  List<TelemetryEntry> query({
    String? kind,
    String? level,
    String? env,
    String? text,
    String? installId,
    DateTime? since,
    int limit = 200,
  }) {
    final needle = text?.toLowerCase();
    final out = <TelemetryEntry>[];
    for (final e in _recent.toList().reversed) {
      if (kind != null && e.kind != kind) continue;
      if (level != null && e.level != level) continue;
      if (env != null && e.env != env) continue;
      if (installId != null && e.installId != installId) continue;
      if (since != null && e.time.isBefore(since)) continue;
      if (needle != null &&
          !'${e.name} ${e.message ?? ''} ${jsonEncode(e.data)}'
              .toLowerCase()
              .contains(needle)) {
        continue;
      }
      out.add(e);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Resumen para el panel: conteos por tipo y nombre, errores frecuentes,
  /// instalaciones activas y victorias por perfil (balance real).
  Map<String, Object?> summary({DateTime? since}) {
    final events = <String, int>{};
    final errors = <String, int>{};
    final installs = <String>{};
    final profiles = <String, Map<String, num>>{};
    final versions = <String, int>{};
    for (final e in _recent) {
      if (since != null && e.time.isBefore(since)) continue;
      installs.add(e.installId);
      versions[e.appVersion] = (versions[e.appVersion] ?? 0) + 1;
      switch (e.kind) {
        case 'event':
          events[e.name] = (events[e.name] ?? 0) + 1;
          if (e.name == 'battle_end') _addBattle(profiles, e.data);
        case 'error':
          final key = '${e.name}: ${(e.message ?? '').split('\n').first}';
          errors[key] = (errors[key] ?? 0) + 1;
      }
    }
    List<Map<String, Object?>> top(Map<String, int> m) {
      final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return [for (final e in sorted.take(20)) {'name': e.key, 'count': e.value}];
    }

    return {
      'installs': installs.length,
      'entries': _recent.length,
      'events': top(events),
      'errors': top(errors),
      'versions': top(versions),
      'profiles': {
        for (final e in profiles.entries)
          e.key: {
            'battles': e.value['battles'],
            'winRate': e.value['battles'] == 0
                ? 0
                : e.value['wins']! / e.value['battles']!,
          },
      },
    };
  }

  static void _addBattle(Map<String, Map<String, num>> profiles, Map<String, Object?> data) {
    final ids = data['profiles'];
    final won = data['result'] == 'victoria';
    if (ids is! List<Object?>) return;
    for (final id in ids.whereType<String>()) {
      final p = profiles.putIfAbsent(id, () => {'battles': 0, 'wins': 0});
      p['battles'] = p['battles']! + 1;
      if (won) p['wins'] = p['wins']! + 1;
    }
  }
}
