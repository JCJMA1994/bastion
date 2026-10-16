import 'package:bastion/game/battle_controller.dart';
import 'package:bastion/screens/tutorial_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_engine/rules_engine.dart';

const _rifle = Weapon(
    id: 'fusil', name: 'Fusil', range: 24, attacks: 1, strength: 3, ap: 0, damage: 1);
const _profile = UnitProfile(
  id: 'linea',
  name: 'Línea',
  role: Role.linea,
  soldiers: 3,
  stats: Stats(mov: 6, pun: 4, res: 3, sal: 5, her: 1, mor: 7),
  weapons: [_rifle],
);

BattleState _state() => BattleState(board: const Board(), squads: [
      Squad.deploy(
          id: 'J', side: Side.jugador, profile: _profile,
          positions: const [Vec2(5, 5), Vec2(5, 6.5), Vec2(5, 8)]),
      Squad.deploy(
          id: 'E', side: Side.enemigo, profile: _profile,
          positions: const [Vec2(39, 5), Vec2(39, 6.5), Vec2(39, 8)]),
    ]);

void main() {
  test('la IA juega su turno y devuelve el control al jugador', () {
    final state = _state();
    BattleController(BattleEngine(state: state, dice: SeededDice(3)))..start();
    // Si empezó el enemigo, ya jugó; si empezó el jugador, es su turno.
    expect(state.activeSide, Side.jugador);
  });

  test('arrastrar y soltar mueve la escuadra activa', () {
    final state = _state();
    final controller =
        BattleController(BattleEngine(state: state, dice: ScriptedDice([6, 1])))
          ..start()
          ..select('J')
          ..activateSelected()
          ..dragActive(const Vec2(4, 0));
    expect(controller.ghost, isNotNull);
    controller.dropActive();
    expect(state.squadById('J').soldiers.first.position.x, closeTo(9, 1e-9));
    expect(controller.lastError, isNull);
  });

  test('el tutorial avanza con lo que hace el jugador', () {
    final state = _state();
    final controller =
        BattleController(BattleEngine(state: state, dice: ScriptedDice([6, 1])))
          ..start();
    int? step() => TutorialBanner(battle: controller, onSkip: () {}).step;

    expect(step(), 0);
    controller.select('J');
    expect(step(), 1);
    controller.activateSelected();
    expect(step(), 2);
    controller
      ..dragActive(const Vec2(2, 0))
      ..dropActive();
    expect(step(), 3);
    controller.select('E');
    expect(step(), 4);
  });
}
