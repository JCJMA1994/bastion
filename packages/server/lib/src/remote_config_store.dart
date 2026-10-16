import 'dart:convert';
import 'dart:io';

/// Configuración remota por entorno, leída de `config/<env>.json`. Se relee
/// cuando cambia el archivo, así que se puede editar sin reiniciar.
final class RemoteConfigStore {
  RemoteConfigStore(this.directory);

  final Directory directory;
  final Map<String, (DateTime, Map<String, Object?>, String)> _cache = {};

  static const environments = {'dev', 'qa', 'prod'};

  /// Valores y versión (ETag) del entorno, o nulo si no existe.
  (Map<String, Object?>, String)? read(String env) {
    if (!environments.contains(env)) return null;
    final file = File('${directory.path}/$env.json');
    if (!file.existsSync()) return null;
    final modified = file.lastModifiedSync();
    final cached = _cache[env];
    if (cached != null && cached.$1 == modified) return (cached.$2, cached.$3);
    final raw = file.readAsStringSync();
    final values = jsonDecode(raw) as Map<String, Object?>;
    final etag = '"${raw.hashCode.toUnsigned(32).toRadixString(16)}-${raw.length}"';
    _cache[env] = (modified, values, etag);
    return (values, etag);
  }
}
