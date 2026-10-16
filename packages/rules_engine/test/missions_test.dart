import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Activa y termina escuadras en orden hasta que acaba la batalla.
void passUntilEnd(BattleEngine engine) {
  final state = engine.state;
  var guard = 0;
  while (state.step != BattleStep.terminada && guard++ < 100) {
    final squad = state
        .aliveSquadsOf(state.activeSide!)
        .firstWhere((s) => !s.activatedThisRound);
    engine
      ..apply(ActivateSquad(squad.id))
      ..apply(const EndActivation());
  }
}

void main() {
  const bridge = Board(objectives: [
    Objective(id: 'puente', position: Vec2(22, 14)),
  ]);

  group('Defensa del vado', () {
    test('el atacante gana en cuanto controla el puente desde la ronda 2', () {
      final engine = startBattle([
        squad('J1', Side.jugador, [const Vec2(3, 2)]),
        squad('E1', Side.enemigo, column(22, 13, 2)),
      ], ScriptedDice([...playerFirst, ...playerFirst]),
          board: bridge, mission: DefensaDelVado(defender: Side.jugador));
      passUntilEnd(engine);

      expect(engine.state.round, 2);
      expect(engine.state.winner, Side.enemigo);
    });

    test('el defensor gana si controla el puente al final de la ronda 4', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(22, 13, 2)),
        squad('E1', Side.enemigo, [const Vec2(41, 2)]),
      ], ScriptedDice([...playerFirst, ...playerFirst]),
          board: bridge, mission: DefensaDelVado(defender: Side.jugador));
      passUntilEnd(engine);

      expect(engine.state.round, 4);
      expect(engine.state.winner, Side.jugador);
    });
  });

  test('Reconocimiento revela objetivos al contacto y solo puntúa los reales',
      () {
    final mission = Reconocimiento();
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 5, 2)),
      squad('E1', Side.enemigo, column(39, 5, 2)),
    ], ScriptedDice([
      1, 1, // o1 real
      1, 2, // de [o2, o3, o4, o5], índice 1: o3 real
      1, 1, // de [o2, o4, o5], índice 0: o2 real
      ...playerFirst,
    ]),
        board: const Board(objectives: standardObjectives),
        mission: mission);

    expect(mission.real, {'o1', 'o3', 'o2'});
    engine.apply(const ActivateSquad('J1'));
    final events = engine.apply(const EndActivation());
    final revealed = {
      for (final e in events.whereType<ObjectiveRevealed>()) e.objectiveId: e.real,
    };
    expect(revealed, {'o1': true, 'o4': false});
  });

  group('Despliegue', () {
    test('fuera de la zona es inválido; Infiltración amplía 6"', () {
      const scouts = UnitProfile(
        id: 'exploradores_test',
        name: 'Exploradores',
        role: Role.linea,
        soldiers: 2,
        stats: Stats(mov: 8, pun: 4, res: 3, sal: 6, her: 1, mor: 6),
        weapons: [rifle],
        abilities: {Abilities.infiltracion},
      );
      final state = BattleState(board: const Board(), squads: [
        squad('ok', Side.jugador, column(5, 5, 2)),
        squad('fuera', Side.jugador, column(12, 15, 2)),
        squad('infiltrados', Side.jugador, column(12, 20, 2), profile: scouts),
        squad('enemigo', Side.enemigo, column(40, 5, 2)),
      ]);
      final invalid =
          Battlefield(state).invalidDeployments().map((s) => s.id).toList();
      expect(invalid, ['fuera']);
    });
  });
}
