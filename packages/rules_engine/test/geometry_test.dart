import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final rect = Polygon.rect(0, 0, 4, 4);

  test('contiene puntos interiores y no exteriores', () {
    expect(rect.contains(const Vec2(2, 2)), isTrue);
    expect(rect.contains(const Vec2(5, 2)), isFalse);
  });

  test('longitud de un segmento que cruza el polígono', () {
    expect(rect.lengthInside(const Vec2(-1, 2), const Vec2(5, 2)),
        closeTo(4, 1e-9));
  });

  test('distancia entre bordes de peanas', () {
    const a = (center: Vec2(0, 0), radius: 0.5);
    const b = (center: Vec2(3, 0), radius: 0.5);
    expect(edgeDistance(a, b), closeTo(2, 1e-9));
  });

  test('ruinas entre atacante y objetivo dan cobertura', () {
    final state = BattleState(
      board: Board(terrain: [
        TerrainArea(
            id: 'r1', type: TerrainType.ruinas, polygon: Polygon.rect(18, 0, 4, 28)),
      ]),
      squads: [
        squad('J', Side.jugador, column(10, 10, 3)),
        squad('E', Side.enemigo, column(30, 10, 3)),
      ],
    );
    final field = Battlefield(state);
    expect(field.inCover(state.squadById('J'), state.squadById('E')), isTrue);
  });

  test('más de 3" de bosque bloquean la visión', () {
    final state = BattleState(
      board: Board(terrain: [
        TerrainArea(
            id: 'b1', type: TerrainType.bosque, polygon: Polygon.rect(18, 0, 5, 28)),
      ]),
      squads: [
        squad('J', Side.jugador, column(10, 10, 3)),
        squad('E', Side.enemigo, column(30, 10, 3)),
      ],
    );
    final field = Battlefield(state);
    expect(field.isVisible(state.squadById('J'), state.squadById('E')), isFalse);
  });
}
