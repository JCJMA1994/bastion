import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bastion/app/app_controller.dart';
import 'package:bastion/art/art_set.dart';
import 'package:bastion/art/renderers.dart';
import 'package:bastion/data/campaign_repository.dart';
import 'package:bastion/data/game_data.dart';
import 'package:bastion/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_engine/rules_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingRenderer implements TroopRenderer {
  int calls = 0;
  @override
  void drawFigures(ui.Canvas canvas,
      {required Squad squad,
      required List<SoldierDraw> soldiers,
      required ui.Color teamColor,
      required bool roundBase}) {
    calls++;
  }
}

Squad _squad(UnitProfile profile, Side side) => Squad.deploy(
    id: profile.id, side: side, profile: profile, positions: const [Vec2(2, 2)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la escala es la menor que cubre la pantalla', () {
    const available = {'1x': 40.0, '2x': 80.0, '4x': 160.0};
    expect(ArtSet.chooseScale(available, devicePixelRatio: 1), '1x');
    expect(ArtSet.chooseScale(available, devicePixelRatio: 3), '2x');
    expect(ArtSet.chooseScale(available, devicePixelRatio: 3, typicalZoom: 3), '4x');
    expect(ArtSet.chooseScale(available, devicePixelRatio: 9), '4x');
  });

  test('los atlas cargan todas las piezas de la especificación', () async {
    final spec = jsonDecode(File('../art/spec.json').readAsStringSync())
        as Map<String, Object?>;
    final art = await ArtSet.load(devicePixelRatio: 2);
    expect(art, isNotNull);
    expect(art!.ground, isNotNull);
    for (final faction in (spec['factions']! as List).cast<String>()) {
      for (final e in (spec['troops']! as Map<String, Object?>).entries) {
        final states = ((e.value! as Map)['states']! as List).cast<String>();
        for (final state in states) {
          expect(art.frame(faction, e.key, state), isNotNull,
              reason: '$faction/${e.key}_$state');
          expect(art.frame(faction, e.key, state, mask: true), isNotNull,
              reason: '$faction/${e.key}_${state}_mask');
        }
      }
    }
  });

  test('los atlas de terreno y efectos cargan todas sus piezas', () async {
    final spec = jsonDecode(File('../art/spec.json').readAsStringSync())
        as Map<String, Object?>;
    final art = (await ArtSet.load(devicePixelRatio: 2))!;
    for (final kind in (spec['terrain']! as Map<String, Object?>).entries) {
      for (final piece in (kind.value! as Map<String, Object?>).keys) {
        expect(art.terrainPiece(kind.key, piece), isNotNull, reason: '${kind.key}/$piece');
      }
    }
    for (final e in (spec['effects']! as Map<String, Object?>).entries) {
      final frames = ((e.value! as Map)['frames'] as num).toInt();
      expect(art.effectFrames[e.key], frames);
      for (var i = 0; i < frames; i++) {
        expect(art.effectFrame(e.key, i), isNotNull, reason: '${e.key} $i');
      }
    }
    expect(art.terrainSizes['parapeto']!['sacos'], (3.0, 1.0));
  });

  test('sin el recorte, el renderizador de sprites vuelve a vectorial', () async {
    final data = await GameData.load();
    final fallback = _CountingRenderer();
    final renderer = SpriteTroopRenderer(
      ArtSet(scale: '1x', pxPerInch: 40, frames: const {}),
      fallback: fallback,
    );
    final recorder = ui.PictureRecorder();
    renderer.drawFigures(ui.Canvas(recorder),
        squad: _squad(data.catalog['lanceros'], Side.jugador),
        soldiers: const [SoldierDraw(center: ui.Offset(40, 40), radius: 10, facing: 0)],
        teamColor: const ui.Color(0xFFE3A33B),
        roundBase: true);
    recorder.endRecording();
    expect(fallback.calls, 1);
  });

  test('el sprite pinta la figura teñida en su sitio', () async {
    final data = await GameData.load();
    final art = (await ArtSet.load(devicePixelRatio: 2))!;
    final recorder = ui.PictureRecorder();
    SpriteTroopRenderer(art).drawFigures(ui.Canvas(recorder),
        squad: _squad(data.catalog['lanceros'], Side.jugador),
        soldiers: const [SoldierDraw(center: ui.Offset(40, 40), radius: 10, facing: math.pi / 4)],
        teamColor: const ui.Color(0xFFE3A33B),
        roundBase: true);
    final image = await recorder.endRecording().toImage(80, 80);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alphaAt(int x, int y) => bytes.getUint8((y * 80 + x) * 4 + 3);
    expect(alphaAt(40, 40), greaterThan(0), reason: 'hay figura en el centro');
    expect(alphaAt(2, 2), 0, reason: 'fuera de la figura queda transparente');
  });

  group('elección de estilo', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<AppController> app({ArtSet? art}) async => AppController(
          await GameData.load(),
          await CampaignRepository.open(),
          await SettingsController.open(),
          art: art,
        );

    test('sin arte cargado siempre es vectorial', () async {
      final a = await app();
      a.settings.artStyle = ArtStyle.sprites;
      expect(a.renderers.usesSprites, isFalse);
    });

    test('con arte, respeta el ajuste', () async {
      final art = (await ArtSet.load(devicePixelRatio: 2))!;
      final a = await app(art: art);
      a.settings.artStyle = ArtStyle.sprites;
      expect(a.renderers.usesSprites, isTrue);
      a.settings.artStyle = ArtStyle.vector;
      expect(a.renderers.usesSprites, isFalse);
      // Automático sin configuración remota: vectorial, como en prod.
      a.settings.artStyle = ArtStyle.auto;
      expect(a.renderers.usesSprites, isFalse);
    });
  });
}
