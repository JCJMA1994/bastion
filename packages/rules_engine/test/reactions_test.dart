import 'dart:convert';

import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('Deshacer movimiento', () {
    test('devuelve la escuadra a su sitio y permite mover otra vez', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(39, 5, 3)),
      ], ScriptedDice(playerFirst));
      final j1 = engine.state.squadById('J1');
      engine
        ..apply(const ActivateSquad('J1'))
        ..apply(MoveSquad(Planner.translate(j1, const Vec2(4, 0))))
        ..apply(const UndoMove());
      expect(j1.soldiers.first.position, const Vec2(5, 5));
      expect(engine.state.progress!.moved, isFalse);

      engine.apply(MoveSquad(Planner.translate(j1, const Vec2(6, 0))));
      expect(j1.soldiers.first.position.x, closeTo(11, 1e-9));
    });

    test('sin movimiento no hay nada que deshacer', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(39, 5, 3)),
      ], ScriptedDice(playerFirst));
      engine.apply(const ActivateSquad('J1'));
      expect(
        () => engine.apply(const UndoMove()),
        throwsA(isA<RuleViolation>()
            .having((v) => v.code, 'code', ViolationCode.nadaQueDeshacer)),
      );
    });
  });

  group('Vigilar', () {
    test('dispara con −1 al enemigo que se mueve a su alcance', () {
      final dice = ScriptedDice([
        ...playerFirst,
        5, 4, 6, // impactar con −1: 5 y 6 impactan, el 4 no
        6, 6, // hieren
        1, 1, // no salvan
        1, 1, // moral superada al terminar la activación
        ...playerFirst, // iniciativa de la ronda 2
      ]);
      final engine = startBattle([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(32, 5, 3)),
      ], dice);
      final e1 = engine.state.squadById('E1');
      engine
        ..apply(const ActivateSquad('J1'))
        ..apply(const Overwatch())
        ..apply(const ActivateSquad('E1'));
      final events =
          engine.apply(MoveSquad(Planner.translate(e1, const Vec2(-4, 0))));

      expect(events.whereType<OverwatchTriggered>().single.watcherId, 'J1');
      final attack = events.whereType<AttackResolved>().single;
      expect(attack.reaction, isTrue);
      expect(attack.rolls.hitRolls, [5, 4, 6]);
      expect(attack.rolls.hitModifier, -1);
      expect(attack.killed, 2);
      expect(engine.state.squadById('J1').overwatch, isFalse);
      expect(
        () => engine.apply(const UndoMove()),
        throwsA(isA<RuleViolation>()
            .having((v) => v.code, 'code', ViolationCode.nadaQueDeshacer)),
      );
      engine.apply(const EndActivation());
      expect(dice.remaining, 0);
    });

    test('contra una carga dispara antes del cuerpo a cuerpo', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, [const Vec2(9, 6.5)]),
      ], ScriptedDice([...playerFirst, 6, 6, 6, 6, 6, 6, 1, 1, 1]));
      engine
        ..apply(const ActivateSquad('J1'))
        ..apply(const Overwatch())
        ..apply(const ActivateSquad('E1'));
      final events = engine.apply(const Charge(
          targetSquadId: 'J1', destinations: {'E1.0': Vec2(6, 6.5)}));

      expect(events.whereType<ChargeMade>(), isEmpty);
      expect(engine.state.squadById('E1').destroyed, isTrue);
      expect(engine.state.winner, Side.jugador);
    });
  });

  group('Probabilidades', () {
    test('cálculo exacto de bajas y moral', () {
      final odds = AttackOdds.compute(
        dice: 3,
        hitOn: 4,
        woundOn: 4,
        saveOn: 5,
        damage: 1,
        targetWounds: const [1, 1, 1, 1, 1],
        startingCount: 5,
        morale: 7,
      );
      // Cada dado: 1/2 · 1/2 · 2/3 = 1/6 de causar una baja.
      expect(odds.expectedKills, closeTo(0.5, 1e-9));
      expect(odds.anyKillChance, closeTo(1 - 125 / 216, 1e-9));
      expect(odds.destroyChance, 0);
      expect(odds.demoralizeChance, closeTo((1 / 216) * (15 / 36), 1e-9));
      expect(odds.killDistribution.reduce((a, b) => a + b), closeTo(1, 1e-9));
    });

    test('el daño no se desborda entre soldados', () {
      final odds = AttackOdds.compute(
        dice: 2,
        hitOn: null,
        woundOn: 2,
        saveOn: null,
        damage: 2,
        targetWounds: const [3, 3],
        startingCount: 2,
        morale: 7,
      );
      // Dos heridas de D2 contra HER3: como mucho una baja.
      expect(odds.killDistribution, hasLength(3));
      expect(odds.killDistribution[2], 0);
    });

    test('la previsión del motor usa las reglas vigentes', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(20, 5, 5)),
      ], ScriptedDice(playerFirst));
      engine.apply(const ActivateSquad('J1'));
      final odds = engine.previewShot('J1', 'E1', 'fusil')!;
      expect(odds.hitOn, 4);
      expect(odds.hitModifier, 0);
      expect(odds.expectedKills, closeTo(0.5, 1e-9));
      expect(engine.previewShot('J1', 'E1', 'bayoneta'), isNull);
    });
  });

  test('los comandos nuevos sobreviven a JSON', () {
    for (final c in const <Command>[UndoMove(), Overwatch()]) {
      final copy = Command.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
      expect(copy.toJson(), c.toJson());
    }
  });
}
