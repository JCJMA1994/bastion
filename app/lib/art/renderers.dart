import 'dart:typed_data';
import 'dart:ui';

import 'package:rules_engine/rules_engine.dart' show Role, Side, Squad, TerrainArea;

import '../theme/bastion_tokens.dart';
import 'art_set.dart';
import 'decor.dart';

/// Un soldado a dibujar, en unidades del mundo.
class SoldierDraw {
  const SoldierDraw({
    required this.center,
    required this.radius,
    required this.facing,
    this.alpha = 1,
    this.fallen = false,
    this.firing = false,
  });

  final Offset center;

  /// Radio de la peana.
  final double radius;

  /// Orientación en radianes (0 = derecha).
  final double facing;
  final double alpha;
  final bool fallen;

  /// Acaba de atacar: pose de disparo si el arte la tiene.
  final bool firing;
}

/// Dibuja las figuras de los soldados (no la peana ni los anillos, que son
/// siempre código para mantener la legibilidad).
abstract interface class TroopRenderer {
  void drawFigures(
    Canvas canvas, {
    required Squad squad,
    required List<SoldierDraw> soldiers,
    required Color teamColor,
    required bool roundBase,
  });
}

/// Dibuja el suelo y las áreas de terreno.
abstract interface class TerrainRenderer {
  /// Pinta el fondo del tablero ([size] en unidades del mundo).
  void drawGround(Canvas canvas, Size size);

  /// Pinta un área de terreno ya convertida a [path].
  void drawArea(Canvas canvas, TerrainArea area, Path path);

  /// Pinta un marcador de objetivo; [central] vale 2 PV.
  void drawObjective(Canvas canvas, Offset center, double radius, {required bool central});

  /// Opacidad de la cuadrícula de 1" sobre este suelo.
  double get gridAlpha;
}

/// Dibuja los efectos de un instante; [t] va de 0 a 1.
abstract interface class EffectsRenderer {
  void drawTracer(Canvas canvas, Offset from, Offset to, double t, {required bool hit});
  void drawBlast(Canvas canvas, Offset center, double radius, double t);
}

/// Los tres renderizadores de una partida.
class Renderers {
  const Renderers({required this.troops, required this.terrain, required this.effects});

  /// Estilo vectorial: todo por código.
  const Renderers.vector()
      : troops = const VectorTroopRenderer(),
        terrain = const VectorTerrainRenderer(),
        effects = const VectorEffectsRenderer();

  /// Estilo de sprites con [art]; lo que falte se dibuja en vectorial.
  /// [decor] fija la decoración a mano por área (de `maps.json`).
  Renderers.sprites(ArtSet art,
      {double worldPerInch = 20, Map<String, List<DecorItem>> decor = const {}})
      : troops = SpriteTroopRenderer(art, worldPerInch: worldPerInch),
        terrain = SpriteTerrainRenderer(art,
            worldPerInch: worldPerInch,
            planner: DecorPlanner(sizes: art.terrainSizes, explicit: decor)),
        effects = SpriteEffectsRenderer(art, worldPerInch: worldPerInch);

  final TroopRenderer troops;
  final TerrainRenderer terrain;
  final EffectsRenderer effects;

  bool get usesSprites => troops is SpriteTroopRenderer;
}

// ---------------------------------------------------------------- vectorial

/// Siluetas por rol vistas desde arriba, dibujadas con formas.
class VectorTroopRenderer implements TroopRenderer {
  const VectorTroopRenderer();

  @override
  void drawFigures(
    Canvas canvas, {
    required Squad squad,
    required List<SoldierDraw> soldiers,
    required Color teamColor,
    required bool roundBase,
  }) {
    for (final s in soldiers) {
      // En el rombo hay menos sitio: la figura se reduce un poco.
      _figure(canvas, squad.profile.role, s.center, s.radius * (roundBase ? 1 : 0.8),
          s.facing, s.alpha);
    }
  }

  static void _figure(
      Canvas canvas, Role role, Offset c, double r, double facing, double alpha) {
    final ink = BastionColors.mesa900.withValues(alpha: 0.85 * alpha);
    final stroke = Paint()
      ..color = ink
      ..strokeWidth = r * 0.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = ink;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(facing);
    Offset p(double x, double y) => Offset(x * r, y * r);
    switch (role) {
      case Role.mando:
        canvas
          ..drawLine(p(-0.25, 0.35), p(-0.25, -0.75), stroke)
          ..drawPath(
              Path()
                ..moveTo(-0.25 * r, -0.75 * r)
                ..lineTo(0.45 * r, -0.55 * r)
                ..lineTo(-0.25 * r, -0.35 * r)
                ..close(),
              fill)
          ..drawCircle(p(0.05, 0.1), r * 0.26, fill);
      case Role.linea:
        canvas
          ..drawLine(p(0, 0.3), p(0.95, 0.3), stroke)
          ..drawCircle(p(-0.1, 0), r * 0.28, fill);
      case Role.apoyo:
        canvas
          ..drawLine(p(-0.1, 0.3), p(1.05, 0.3), stroke)
          ..drawCircle(p(0.5, 0.3), r * 0.14, fill)
          ..drawCircle(p(-0.15, 0), r * 0.28, fill);
      case Role.asalto:
        canvas
          ..drawLine(p(0, -0.3), p(0.65, -0.3), stroke)
          ..drawRect(Rect.fromLTRB(0.55 * r, -0.62 * r, 0.85 * r, -0.05 * r), fill)
          ..drawCircle(p(-0.1, 0.05), r * 0.3, fill);
      case Role.caballeria:
        canvas
          ..drawOval(
              Rect.fromCenter(center: p(0.05, 0), width: 1.5 * r, height: 0.6 * r),
              Paint()..color = ink.withValues(alpha: 0.4 * alpha))
          ..drawCircle(p(0.75, 0), r * 0.16, fill)
          ..drawCircle(p(-0.1, 0), r * 0.24, fill);
      case Role.artilleria:
        canvas
          ..drawRect(Rect.fromLTRB(-0.35 * r, -0.14 * r, 1.0 * r, 0.14 * r), fill)
          ..drawCircle(p(-0.1, -0.5), r * 0.22, stroke)
          ..drawCircle(p(-0.1, 0.5), r * 0.22, stroke);
    }
    canvas.restore();
  }
}

/// Campo liso y áreas de terreno en color.
class VectorTerrainRenderer implements TerrainRenderer {
  const VectorTerrainRenderer();

  @override
  double get gridAlpha => 0.07;

  @override
  void drawGround(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = BastionColors.campo);

  @override
  void drawArea(Canvas canvas, TerrainArea area, Path path) =>
      _drawAreaVector(canvas, area, path, fillAlpha: 0.6);

  @override
  void drawObjective(Canvas canvas, Offset center, double radius,
          {required bool central}) =>
      _drawObjectiveVector(canvas, center, radius, central: central, fill: true);
}

void _drawObjectiveVector(Canvas canvas, Offset center, double radius,
    {required bool central, required bool fill}) {
  if (fill) {
    canvas.drawCircle(
        center, radius, Paint()..color = BastionColors.mesa900.withValues(alpha: 0.75));
  }
  canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = central ? BastionColors.latonClaro : BastionColors.tinta
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
}

/// Dibuja recortes de un atlas en lote: una llamada por página.
class _AtlasBatch {
  final Map<Image, (List<RSTransform>, List<Rect>, List<Color>)> _groups = {};

  void add(ArtFrame frame,
      {required Offset at, required double scale, double rotation = 0, double alpha = 1}) {
    final g = _groups.putIfAbsent(frame.image, () => ([], [], []));
    g.$1.add(RSTransform.fromComponents(
      rotation: rotation,
      scale: scale,
      anchorX: frame.source.width / 2,
      anchorY: frame.source.height / 2,
      translateX: at.dx,
      translateY: at.dy,
    ));
    g.$2.add(frame.source);
    g.$3.add(Color.fromRGBO(255, 255, 255, alpha));
  }

  bool get isEmpty => _groups.isEmpty;

  void draw(Canvas canvas, Paint paint) => _groups.forEach((image, g) =>
      canvas.drawAtlas(image, g.$1, g.$2, g.$3, BlendMode.modulate, null, paint));
}

void _drawAreaVector(Canvas canvas, TerrainArea area, Path path,
    {required double fillAlpha}) {
  final color = switch (area.type.name) {
    'bosque' => BastionColors.terrenoBosque,
    'muroBajo' => BastionColors.tintaSuave,
    _ => BastionColors.terrenoRuina,
  };
  canvas
    ..drawPath(path, Paint()..color = color.withValues(alpha: fillAlpha))
    ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
}

/// Trazas y onda del cañón con formas.
class VectorEffectsRenderer implements EffectsRenderer {
  const VectorEffectsRenderer();

  @override
  void drawTracer(Canvas canvas, Offset from, Offset to, double t, {required bool hit}) {
    final head = Offset.lerp(from, to, (t * 1.6).clamp(0.0, 1.0))!;
    final tail = Offset.lerp(from, to, ((t - 0.25) * 1.6).clamp(0.0, 1.0))!;
    canvas.drawLine(
        tail,
        head,
        Paint()
          ..color = BastionColors.latonClaro.withValues(alpha: 1 - t * 0.6)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    if (hit && t > 0.6) {
      final k = (t - 0.6) / 0.4;
      canvas.drawCircle(
          to,
          6 + 10 * k,
          Paint()
            ..color = BastionColors.peligro.withValues(alpha: 1 - k)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  void drawBlast(Canvas canvas, Offset center, double radius, double t) {
    final r = radius * (0.3 + 0.7 * t);
    canvas
      ..drawCircle(center, r,
          Paint()..color = BastionColors.peligro.withValues(alpha: 0.25 * (1 - t)))
      ..drawCircle(
          center,
          r,
          Paint()
            ..color = BastionColors.peligro.withValues(alpha: 1 - t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
  }
}

// ---------------------------------------------------------------- sprites

/// Figuras del atlas, dibujadas con `drawAtlas`: una llamada por página para
/// las figuras y otra para las máscaras teñidas con el color del bando.
class SpriteTroopRenderer implements TroopRenderer {
  SpriteTroopRenderer(this.art,
      {this.worldPerInch = 20, this.fallback = const VectorTroopRenderer()});

  final ArtSet art;
  final double worldPerInch;

  /// Para perfiles o estados que no estén en el atlas.
  final TroopRenderer fallback;

  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Facción del arte según el bando (el color lo pone la máscara).
  static String factionFor(Side side) => side == Side.jugador ? 'compania' : 'columna';

  @override
  void drawFigures(
    Canvas canvas, {
    required Squad squad,
    required List<SoldierDraw> soldiers,
    required Color teamColor,
    required bool roundBase,
  }) {
    if (soldiers.isEmpty) return;
    final faction = factionFor(squad.side);
    final profile = squad.profile.id;
    ArtFrame? find(SoldierDraw s, {bool mask = false}) =>
        (s.fallen ? art.frame(faction, profile, 'caida', mask: mask) : null) ??
        (s.firing ? art.frame(faction, profile, 'disparo', mask: mask) : null) ??
        art.frame(faction, profile, 'reposo', mask: mask);

    final missing = soldiers.any((s) => find(s) == null || find(s, mask: true) == null);
    if (missing) {
      fallback.drawFigures(canvas,
          squad: squad, soldiers: soldiers, teamColor: teamColor, roundBase: roundBase);
      return;
    }

    final scale = worldPerInch / art.pxPerInch;
    for (final mask in const [false, true]) {
      // Agrupado por imagen de página: normalmente es una sola llamada.
      final groups = <Image, (List<RSTransform>, List<Rect>, List<Color>)>{};
      for (final s in soldiers) {
        final frame = find(s, mask: mask)!;
        final group = groups.putIfAbsent(frame.image, () => ([], [], []));
        group.$1.add(RSTransform.fromComponents(
          rotation: s.facing,
          scale: scale,
          anchorX: frame.source.width / 2,
          anchorY: frame.source.height / 2,
          translateX: s.center.dx,
          translateY: s.center.dy,
        ));
        group.$2.add(frame.source);
        group.$3.add(mask
            ? teamColor.withValues(alpha: s.alpha)
            : Color.fromRGBO(255, 255, 255, s.alpha));
      }
      groups.forEach((image, g) => canvas.drawAtlas(
          image, g.$1, g.$2, g.$3, BlendMode.modulate, null, _paint));
    }
  }
}

/// Suelo con textura en mosaico; las áreas siguen en color, más tenues,
/// hasta que llegue la decoración (fase F4 del plan de arte).
class SpriteTerrainRenderer implements TerrainRenderer {
  SpriteTerrainRenderer(this.art,
      {this.worldPerInch = 20,
      this.fallback = const VectorTerrainRenderer(),
      DecorPlanner? planner})
      : planner = planner ?? DecorPlanner(sizes: art.terrainSizes);

  final ArtSet art;
  final double worldPerInch;
  final TerrainRenderer fallback;
  final DecorPlanner planner;
  Paint? _groundPaint;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  @override
  double get gridAlpha => art.ground == null ? fallback.gridAlpha : 0.05;

  @override
  void drawGround(Canvas canvas, Size size) {
    final ground = art.ground;
    final ppi = art.groundPxPerInch;
    if (ground == null || ppi == null) {
      fallback.drawGround(canvas, size);
      return;
    }
    final k = worldPerInch / ppi;
    _groundPaint ??= Paint()
      ..filterQuality = FilterQuality.medium
      ..shader = ImageShader(ground, TileMode.repeated, TileMode.repeated,
          Float64List.fromList([k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    canvas.drawRect(Offset.zero & size, _groundPaint!);
  }

  /// El área sigue marcada en color tenue (es la zona que cuenta para las
  /// reglas) y encima van sus piezas decorativas.
  @override
  void drawArea(Canvas canvas, TerrainArea area, Path path) {
    final items = planner.forArea(area);
    _drawAreaVector(canvas, area, path, fillAlpha: items.isEmpty ? 0.45 : 0.22);
    final batch = _AtlasBatch();
    final base = worldPerInch / art.pxPerInch;
    for (final item in items) {
      final frame = art.terrainPiece(item.kind, item.piece);
      if (frame == null) continue;
      batch.add(frame,
          at: Offset(item.center.x * worldPerInch, item.center.y * worldPerInch),
          scale: base * item.scale,
          rotation: item.rotation);
    }
    batch.draw(canvas, _paint);
  }

  @override
  void drawObjective(Canvas canvas, Offset center, double radius,
      {required bool central}) {
    final frame = art.terrainPiece('objetivo', central ? 'central' : 'normal');
    if (frame == null) {
      fallback.drawObjective(canvas, center, radius, central: central);
      return;
    }
    (_AtlasBatch()
          ..add(frame, at: center, scale: worldPerInch / art.pxPerInch))
        .draw(canvas, _paint);
    // El anillo se mantiene: marca la zona que puntúa.
    _drawObjectiveVector(canvas, center, radius, central: central, fill: false);
  }
}

/// Efectos por fotogramas sobre las trazas vectoriales: fogonazo y humo en
/// el tirador, polvo en el impacto y explosión del cañón.
class SpriteEffectsRenderer implements EffectsRenderer {
  SpriteEffectsRenderer(this.art,
      {this.worldPerInch = 20, this.fallback = const VectorEffectsRenderer()});

  final ArtSet art;
  final double worldPerInch;
  final EffectsRenderer fallback;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Fotograma de [effect] para el tramo [t0]–[t1] del efecto, o nulo.
  ArtFrame? _frameAt(String effect, double t, double t0, double t1) {
    final frames = art.effectFrames[effect] ?? 0;
    if (frames == 0 || t < t0 || t > t1) return null;
    final index = ((t - t0) / (t1 - t0) * frames).floor().clamp(0, frames - 1);
    return art.effectFrame(effect, index);
  }

  @override
  void drawTracer(Canvas canvas, Offset from, Offset to, double t, {required bool hit}) {
    fallback.drawTracer(canvas, from, to, t, hit: false);
    final scale = worldPerInch / art.pxPerInch;
    final angle = (to - from).direction;
    final batch = _AtlasBatch();
    final smoke = _frameAt('humo', t, 0.1, 1);
    if (smoke != null) batch.add(smoke, at: from, scale: scale);
    final flash = _frameAt('fogonazo', t, 0, 0.3);
    if (flash != null) batch.add(flash, at: from, scale: scale, rotation: angle);
    final dust = hit ? _frameAt('impacto', t, 0.55, 1) : null;
    if (dust != null) batch.add(dust, at: to, scale: scale);
    if (batch.isEmpty && hit) {
      fallback.drawTracer(canvas, from, to, t, hit: true);
      return;
    }
    batch.draw(canvas, _paint);
  }

  @override
  void drawBlast(Canvas canvas, Offset center, double radius, double t) {
    final frame = _frameAt('explosion', t, 0, 1);
    if (frame == null) {
      fallback.drawBlast(canvas, center, radius, t);
      return;
    }
    (_AtlasBatch()..add(frame, at: center, scale: 2 * radius / frame.source.width))
        .draw(canvas, _paint);
  }
}
