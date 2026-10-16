import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../telemetry/telemetry.dart';

/// Un recorte de un atlas.
class ArtFrame {
  const ArtFrame(this.image, this.source);

  final ui.Image image;
  final ui.Rect source;
}

/// Arte cargado para una escala (1x, 2x o 4x): figuras de tropas por
/// facción, perfil y estado, y textura de suelo. Se genera con
/// `tool/pack_art.sh` a partir de `art/source/`.
class ArtSet {
  ArtSet({
    required this.scale,
    required this.pxPerInch,
    required Map<String, ArtFrame> frames,
    Map<String, ArtFrame> terrain = const {},
    Map<String, ArtFrame> effects = const {},
    this.terrainSizes = const {},
    this.effectFrames = const {},
    this.ground,
    this.groundPxPerInch,
  })  : _frames = frames,
        _terrain = terrain,
        _effects = effects;

  /// Escala elegida: "1x", "2x" o "4x".
  final String scale;

  /// Píxeles del atlas por pulgada de juego en esta escala.
  final double pxPerInch;
  final Map<String, ArtFrame> _frames;
  final Map<String, ArtFrame> _terrain;
  final Map<String, ArtFrame> _effects;

  /// Piezas de terreno disponibles: tipo → pieza → tamaño en pulgadas.
  final Map<String, Map<String, (double, double)>> terrainSizes;

  /// Fotogramas de cada efecto.
  final Map<String, int> effectFrames;

  /// Textura de suelo en mosaico, si la hay.
  final ui.Image? ground;
  final double? groundPxPerInch;

  int get frameCount => _frames.length;

  /// Figura o máscara de `faccion/perfil_estado`, o nula si falta.
  ArtFrame? frame(String faction, String profile, String state, {bool mask = false}) =>
      _frames['$faction/${profile}_$state${mask ? '_mask' : ''}'];

  /// Pieza de terreno `tipo/pieza`, o nula si falta.
  ArtFrame? terrainPiece(String kind, String piece) => _terrain['$kind/$piece'];

  /// Fotograma [index] del efecto, o nulo si falta.
  ArtFrame? effectFrame(String effect, int index) =>
      _effects['${effect}_${index.toString().padLeft(2, '0')}'];

  static const _root = 'assets/art';

  /// Elige la escala más pequeña que cubre la pantalla: píxeles por pulgada
  /// necesarios = pulgada del mundo × escala del tablero en pantalla ×
  /// densidad × zoom habitual.
  static String chooseScale(
    Map<String, double> available, {
    required double devicePixelRatio,
    double worldPerInch = 20,
    double boardToScreen = 0.6,
    double typicalZoom = 2,
  }) {
    final needed = worldPerInch * boardToScreen * devicePixelRatio * typicalZoom;
    final sorted = available.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final e in sorted) {
      if (e.value >= needed) return e.key;
    }
    return sorted.last.key;
  }

  /// Carga el manifiesto y los atlas de la escala adecuada. Devuelve nulo si
  /// falta algo: el juego sigue con el estilo vectorial.
  static Future<ArtSet?> load({
    AssetBundle? bundle,
    required double devicePixelRatio,
    String groundTheme = 'tierra',
  }) async {
    final assets = bundle ?? rootBundle;
    try {
      final manifest = jsonDecode(await assets.loadString('$_root/manifest.json'))
          as Map<String, Object?>;
      final ppi = {
        for (final e in (manifest['pxPerInch']! as Map<String, Object?>).entries)
          e.key: (e.value! as num).toDouble(),
      };
      final scale = chooseScale(ppi, devicePixelRatio: devicePixelRatio);
      final atlases = manifest['atlases']! as Map<String, Object?>;

      Future<Map<String, ArtFrame>> family(String name) async {
        final frames = <String, ArtFrame>{};
        final byScale = atlases[name] as Map<String, Object?>?;
        final files = (byScale?[scale] as List<Object?>?) ?? const [];
        for (final file in files.cast<String>()) {
          final json = jsonDecode(await assets.loadString('$_root/$file'))
              as Map<String, Object?>;
          final meta = json['meta']! as Map<String, Object?>;
          final image = await _image(assets, '$_root/${meta['image']}');
          for (final e in (json['frames']! as Map<String, Object?>).entries) {
            final f = (e.value! as Map<String, Object?>)['frame']! as Map<String, Object?>;
            frames[e.key] = ArtFrame(
              image,
              ui.Rect.fromLTWH(
                (f['x']! as num).toDouble(),
                (f['y']! as num).toDouble(),
                (f['w']! as num).toDouble(),
                (f['h']! as num).toDouble(),
              ),
            );
          }
        }
        return frames;
      }

      final frames = await family('troops');
      final terrain = await family('terrain');
      final effects = await family('effects');
      final terrainSizes = <String, Map<String, (double, double)>>{
        for (final kind in ((manifest['terrain'] as Map<String, Object?>?) ?? const {}).entries)
          kind.key: {
            for (final piece in (kind.value! as Map<String, Object?>).entries)
              piece.key: (
                ((piece.value! as List<Object?>)[0]! as num).toDouble(),
                ((piece.value! as List<Object?>)[1]! as num).toDouble(),
              ),
          },
      };
      final effectFrames = <String, int>{
        for (final e in ((manifest['effects'] as Map<String, Object?>?) ?? const {}).entries)
          e.key: (e.value! as num).toInt(),
      };
      final groundEntry =
          (manifest['ground'] as Map<String, Object?>?)?[groundTheme] as Map<String, Object?>?;
      final groundFile = groundEntry?[scale] as String?;
      final ground =
          groundFile == null ? null : await _image(assets, '$_root/$groundFile');
      Telemetry.instance.info('art', 'Arte cargado', data: {
        'scale': scale,
        'troops': frames.length,
        'terrain': terrain.length,
        'effects': effects.length,
      });
      return ArtSet(
        scale: scale,
        pxPerInch: ppi[scale]!,
        frames: frames,
        terrain: terrain,
        effects: effects,
        terrainSizes: terrainSizes,
        effectFrames: effectFrames,
        ground: ground,
        groundPxPerInch: ground == null ? null : ppi[scale],
      );
    } on Object catch (e, st) {
      Telemetry.instance.error(e, st, name: 'art_load');
      return null;
    }
  }

  static Future<ui.Image> _image(AssetBundle assets, String path) async {
    final data = await assets.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }
}
