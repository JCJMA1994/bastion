import 'dart:math' as math;

import 'package:rules_engine/rules_engine.dart' show TerrainArea, TerrainType, Vec2;

/// Una pieza decorativa sobre un área de terreno. Es solo visual: el motor
/// de reglas nunca la ve, así que no cambia coberturas, visión ni distancias.
class DecorItem {
  const DecorItem({
    required this.kind,
    required this.piece,
    required this.center,
    this.rotation = 0,
    this.scale = 1,
  });

  /// Desde `maps.json`: `{"pieza": "ruinas/muro", "x": 17, "y": 4,
  /// "rot": 90, "escala": 1}` (rot en grados).
  factory DecorItem.fromJson(Map<String, Object?> json) {
    final parts = (json['pieza']! as String).split('/');
    return DecorItem(
      kind: parts.first,
      piece: parts.last,
      center: Vec2((json['x']! as num).toDouble(), (json['y']! as num).toDouble()),
      rotation: ((json['rot'] as num?)?.toDouble() ?? 0) * math.pi / 180,
      scale: (json['escala'] as num?)?.toDouble() ?? 1,
    );
  }

  final String kind;
  final String piece;

  /// Centro en pulgadas del tablero.
  final Vec2 center;

  /// Radianes.
  final double rotation;
  final double scale;
}

/// Decide qué piezas decoran cada área: las fijadas a mano en `maps.json`
/// (lista `decoracion` del área) o, si no hay, unas generadas a partir de la
/// forma del área con una semilla estable.
class DecorPlanner {
  DecorPlanner({required this.sizes, this.explicit = const {}});

  /// Tipo → pieza → tamaño en pulgadas (del manifiesto del arte).
  final Map<String, Map<String, (double, double)>> sizes;

  /// Decoración fijada a mano, por id de área.
  final Map<String, List<DecorItem>> explicit;

  final Map<String, List<DecorItem>> _cache = {};

  /// Lee la decoración fijada a mano de `data/maps.json`.
  static Map<String, List<DecorItem>> explicitFromMaps(Map<String, Object?> json) => {
        for (final map in (json['maps']! as List<Object?>).cast<Map<String, Object?>>())
          for (final area in (map['terreno']! as List<Object?>).cast<Map<String, Object?>>())
            if (area['decoracion'] is List<Object?>)
              area['id']! as String: [
                for (final item
                    in (area['decoracion']! as List<Object?>).cast<Map<String, Object?>>())
                  DecorItem.fromJson(item),
              ],
      };

  /// Tipo de arte de un área de terreno.
  static String kindOf(TerrainArea area) => switch (area.type) {
        TerrainType.ruinas => 'ruinas',
        TerrainType.bosque => 'bosque',
        TerrainType.crater => 'crater',
        TerrainType.muroBajo =>
          area.id.startsWith('parapeto') ? 'parapeto' : 'muro_bajo',
      };

  List<DecorItem> forArea(TerrainArea area) =>
      _cache.putIfAbsent(_key(area), () => explicit[area.id] ?? _generate(area));

  static String _key(TerrainArea area) =>
      '${area.id}:${area.polygon.points.map((p) => '${p.x},${p.y}').join(';')}';

  List<DecorItem> _generate(TerrainArea area) {
    final kind = kindOf(area);
    final pieces = sizes[kind];
    if (pieces == null || pieces.isEmpty) return const [];
    final rng = _Rng(_stableHash(_key(area)));
    final pts = area.polygon.points;
    final minX = pts.map((p) => p.x).reduce(math.min);
    final maxX = pts.map((p) => p.x).reduce(math.max);
    final minY = pts.map((p) => p.y).reduce(math.min);
    final maxY = pts.map((p) => p.y).reduce(math.max);
    final w = maxX - minX, h = maxY - minY;
    final center = Vec2(minX + w / 2, minY + h / 2);
    final items = <DecorItem>[];

    DecorItem item(String piece, Vec2 at, {double rotation = 0, double scale = 1}) =>
        DecorItem(kind: kind, piece: piece, center: at, rotation: rotation, scale: scale);

    /// Punto al azar dentro del área, con [margin] pulgadas de borde.
    Vec2? inside(double margin) {
      for (var i = 0; i < 20; i++) {
        final p = Vec2(minX + margin + rng.next() * math.max(0, w - 2 * margin),
            minY + margin + rng.next() * math.max(0, h - 2 * margin));
        if (area.polygon.contains(p)) return p;
      }
      return null;
    }

    List<String> named(String prefix) =>
        pieces.keys.where((k) => k.startsWith(prefix)).toList()..sort();

    switch (kind) {
      case 'ruinas':
        final floor = pieces['piso_alto'];
        if (area.hasFloor && floor != null) {
          items.add(item('piso_alto', center,
              scale: math.min(w, h) * 0.9 / math.max(floor.$1, floor.$2)));
        }
        final corner = pieces['esquina'];
        if (corner != null && w >= corner.$1 && h >= corner.$2) {
          items.add(item('esquina',
              Vec2(minX + corner.$1 / 2, minY + corner.$2 / 2)));
        }
        if (pieces.containsKey('muro') && w >= 3) {
          items.add(item('muro', Vec2(center.x + w * 0.15, maxY - 0.4)));
        }
        final rubble = named('escombros');
        for (var i = 0; i < 2 + rng.nextInt(2) && rubble.isNotEmpty; i++) {
          final at = inside(0.6);
          if (at != null) {
            items.add(item(rubble[rng.nextInt(rubble.length)], at,
                rotation: rng.next() * math.pi * 2));
          }
        }
      case 'bosque':
        final trees = named('arbol');
        final bushes = named('arbusto');
        const step = 2.2;
        for (var y = minY + 1.1; y < maxY - 0.6; y += step) {
          for (var x = minX + 1.1; x < maxX - 0.6; x += step) {
            final at = Vec2(x + (rng.next() - 0.5) * 0.8, y + (rng.next() - 0.5) * 0.8);
            if (trees.isNotEmpty && area.polygon.contains(at)) {
              items.add(item(trees[rng.nextInt(trees.length)], at,
                  rotation: rng.next() * math.pi * 2, scale: 0.85 + rng.next() * 0.3));
            }
          }
        }
        for (var i = 0; i < 2 && bushes.isNotEmpty; i++) {
          final at = inside(0.5);
          if (at != null) items.add(item(bushes[rng.nextInt(bushes.length)], at));
        }
      case 'crater':
        final craters = named('crater');
        if (craters.isNotEmpty) {
          final pick = craters[rng.nextInt(craters.length)];
          final size = pieces[pick]!;
          items.add(item(pick, center,
              rotation: rng.next() * math.pi * 2,
              scale: math.min(w, h) / math.max(size.$1, size.$2)));
        }
      case 'muro_bajo':
        final segment = pieces['tramo'];
        if (segment != null) {
          final horizontal = w >= h;
          final length = horizontal ? w : h;
          final n = math.max(1, (length / segment.$1).floor());
          final step = length / n;
          for (var i = 0; i < n; i++) {
            final t = (horizontal ? minX : minY) + step * (i + 0.5);
            items.add(item('tramo', horizontal ? Vec2(t, center.y) : Vec2(center.x, t),
                rotation: horizontal ? 0 : math.pi / 2, scale: step / segment.$1));
          }
        }
      case 'parapeto':
        final bags = pieces['sacos'];
        if (bags != null) {
          items.add(item('sacos', center,
              rotation: h > w ? math.pi / 2 : 0,
              scale: math.max(w, h) / bags.$1));
        }
    }
    return items;
  }

  static int _stableHash(String text) =>
      text.codeUnits.fold(0x811C9DC5, (h, c) => ((h ^ c) * 0x01000193) & 0xFFFFFFFF);
}

/// Generador xorshift32: determinista en todas las plataformas.
class _Rng {
  _Rng(int seed) : _s = seed == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;
  int _s;

  int _u32() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x & 0xFFFFFFFF;
    return _s;
  }

  double next() => _u32() / 4294967296.0;
  int nextInt(int max) => _u32() % max;
}
