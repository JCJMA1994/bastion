import 'dart:convert';
import 'dart:io';

import 'package:bastion/art/decor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_engine/rules_engine.dart';

Map<String, Map<String, (double, double)>> _sizes() {
  final spec = jsonDecode(File('../art/spec.json').readAsStringSync())
      as Map<String, Object?>;
  return {
    for (final kind in (spec['terrain']! as Map<String, Object?>).entries)
      kind.key: {
        for (final p in (kind.value! as Map<String, Object?>).entries)
          p.key: (
            ((p.value! as List)[0] as num).toDouble(),
            ((p.value! as List)[1] as num).toDouble(),
          ),
      },
  };
}

void main() {
  final forest = TerrainArea(
      id: 'soto', type: TerrainType.bosque, polygon: Polygon.rect(10, 15, 6, 5));
  final ruins = TerrainArea(
      id: 'granero', type: TerrainType.ruinas, polygon: Polygon.rect(20, 19, 8, 6));

  test('la decoración generada es determinista', () {
    String dump(List<DecorItem> items) => items
        .map((i) => '${i.kind}/${i.piece}@${i.center.x},${i.center.y},${i.rotation}')
        .join('|');
    final a = DecorPlanner(sizes: _sizes()).forArea(forest);
    final b = DecorPlanner(sizes: _sizes()).forArea(forest);
    expect(a, isNotEmpty);
    expect(dump(a), dump(b));
  });

  test('las piezas generadas quedan dentro de su área', () {
    final planner = DecorPlanner(sizes: _sizes());
    for (final area in [forest, ruins]) {
      for (final item in planner.forArea(area)) {
        expect(area.polygon.contains(item.center), isTrue,
            reason: '${item.piece} en ${item.center}');
      }
    }
  });

  test('cada tipo de terreno usa sus piezas', () {
    final planner = DecorPlanner(sizes: _sizes());
    expect(planner.forArea(forest).every((i) => i.kind == 'bosque'), isTrue);
    final parapet = TerrainArea(
        id: 'parapeto_1', type: TerrainType.muroBajo, polygon: Polygon.rect(11.5, 10, 1, 3));
    final bags = planner.forArea(parapet).single;
    expect(bags.piece, 'sacos');
    expect(bags.scale, closeTo(1, 1e-9));
    final wall = TerrainArea(
        id: 'tapia', type: TerrainType.muroBajo, polygon: Polygon.rect(24, 12, 1, 4));
    expect(planner.forArea(wall).map((i) => i.piece).toSet(), {'tramo'});
  });

  test('la decoración fijada en maps.json tiene prioridad', () {
    final maps = jsonDecode(File('../data/maps.json').readAsStringSync())
        as Map<String, Object?>;
    final explicit = DecorPlanner.explicitFromMaps(maps);
    expect(explicit['molino'], hasLength(4));
    final molino = TerrainArea(
        id: 'molino',
        type: TerrainType.ruinas,
        polygon: Polygon.rect(16, 3, 8, 6),
        hasFloor: true);
    final items = DecorPlanner(sizes: _sizes(), explicit: explicit).forArea(molino);
    expect(items.first.piece, 'piso_alto');
    expect(items.first.scale, 1.8);
  });
}
