import 'dart:convert';
import 'dart:io';

/// Persistencia de partidas.
abstract interface class MatchStorage {
  void save(String code, Map<String, Object?> json);
  Iterable<Map<String, Object?>> loadAll();
}

/// Un archivo JSON por partida en [directory].
final class FileMatchStorage implements MatchStorage {
  FileMatchStorage(this.directory) {
    directory.createSync(recursive: true);
  }

  final Directory directory;

  @override
  void save(String code, Map<String, Object?> json) {
    final file = File('${directory.path}/$code.json');
    final tmp = File('${file.path}.tmp')..writeAsStringSync(jsonEncode(json));
    tmp.renameSync(file.path);
  }

  @override
  Iterable<Map<String, Object?>> loadAll() sync* {
    for (final f in directory.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        yield jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      } on FormatException {
        continue;
      }
    }
  }
}

/// En memoria, para tests.
final class MemoryMatchStorage implements MatchStorage {
  final Map<String, Map<String, Object?>> saved = {};

  @override
  void save(String code, Map<String, Object?> json) =>
      saved[code] = jsonDecode(jsonEncode(json)) as Map<String, Object?>;

  @override
  Iterable<Map<String, Object?>> loadAll() => saved.values;
}
