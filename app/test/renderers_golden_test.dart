@Tags(['golden'])
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bastion/art/art_set.dart';
import 'package:bastion/art/renderers.dart';
import 'package:bastion/data/game_data.dart';
import 'package:bastion/theme/bastion_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_engine/rules_engine.dart';

/// Pinta una muestra de terreno y una fila con cada perfil de los dos bandos,
/// con peana dibujada por código como en el juego.
Future<ui.Image> _scene(GameData data, Renderers r) async {
  const w = 440.0, h = 140.0, ppi = 20.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  r.terrain.drawGround(canvas, const ui.Size(w, h));
  final ruin = TerrainArea(
      id: 'r', type: TerrainType.ruinas, polygon: Polygon.rect(18, 0.5, 3, 2));
  r.terrain.drawArea(
      canvas,
      ruin,
      ui.Path()
        ..addPolygon(
            ruin.polygon.points.map((p) => ui.Offset(p.x * ppi, p.y * ppi)).toList(),
            true));
  final forest = TerrainArea(
      id: 'bosque_captura', type: TerrainType.bosque, polygon: Polygon.rect(1, 0.5, 4, 1.6));
  r.terrain.drawArea(
      canvas,
      forest,
      ui.Path()
        ..addPolygon(
            forest.polygon.points.map((p) => ui.Offset(p.x * ppi, p.y * ppi)).toList(),
            true));
  r.terrain.drawObjective(canvas, const ui.Offset(150, 20), 14, central: false);
  r.terrain.drawObjective(canvas, const ui.Offset(200, 20), 14, central: true);
  final profiles = data.catalog.all.toList();
  for (final (row, side) in const [(0, Side.jugador), (1, Side.enemigo)]) {
    final color = side == Side.jugador ? BastionColors.laton : BastionColors.cobalto;
    for (final (i, profile) in profiles.indexed) {
      final c = ui.Offset(30 + i * 50.0, 50 + row * 50.0);
      final base = ui.Paint()..color = color;
      if (side == Side.jugador) {
        canvas.drawCircle(c, 10, base);
      } else {
        canvas.drawPath(
            ui.Path()
              ..moveTo(c.dx, c.dy - 10)
              ..lineTo(c.dx + 10, c.dy)
              ..lineTo(c.dx, c.dy + 10)
              ..lineTo(c.dx - 10, c.dy)
              ..close(),
            base);
      }
      final squad = Squad.deploy(
          id: profile.id, side: side, profile: profile, positions: const [Vec2(0, 0)]);
      r.troops.drawFigures(canvas,
          squad: squad,
          soldiers: [
            SoldierDraw(center: c, radius: 10, facing: row == 0 ? 0 : math.pi),
          ],
          teamColor: color,
          roundBase: side == Side.jugador);
    }
  }
  return recorder.endRecording().toImage(w.toInt(), h.toInt());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captura · estilo vectorial', () async {
    final data = await GameData.load();
    await expectLater(await _scene(data, const Renderers.vector()),
        matchesGoldenFile('goldens/tablero_vectorial.png'));
  });

  test('captura · estilo ilustrado (arte provisional)', () async {
    final data = await GameData.load();
    final art = (await ArtSet.load(devicePixelRatio: 2))!;
    await expectLater(await _scene(data, Renderers.sprites(art)),
        matchesGoldenFile('goldens/tablero_ilustrado.png'));
  });
}
