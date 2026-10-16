import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

import 'support.dart';

BattleEngine engineWith(List<Squad> squads, Dice dice, {Board? board}) {
  final engine = BattleEngine(
    state: BattleState(board: board ?? const Board(), squads: squads),
    dice: dice,
  );
  engine.start();
  return engine;
}

void main() {
  group('activación alterna', () {
    test('los bandos se alternan y la ronda avanza al agotarse', () {
      final engine = engineWith([
        squad('J1', Side.jugador, column(5, 2, 3)),
        squad('J2', Side.jugador, column(5, 15, 3)),
        squad('E1', Side.enemigo, column(39, 2, 3)),
      ], ScriptedDice([...playerFirst, ...playerFirst]));
      final state = engine.state;

      expect(state.activeSide, Side.jugador);
      engine
        ..apply(const ActivateSquad('J1'))
        ..apply(const EndActivation());
      expect(state.activeSide, Side.enemigo);

      expect(() => engine.apply(const ActivateSquad('J2')),
          throwsA(isA<RuleViolation>()));

      engine
        ..apply(const ActivateSquad('E1'))
        ..apply(const EndActivation());
      expect(state.activeSide, Side.jugador);

      engine.apply(const ActivateSquad('J2'));
      final events = engine.apply(const EndActivation());

      expect(events.whereType<RoundStarted>().single.round, 2);
      expect(state.round, 2);
      expect(state.activeSide, Side.jugador);
    });

    test('un comando inválido no cambia el estado', () {
      final engine = engineWith([
        squad('J1', Side.jugador, column(5, 2, 3)),
        squad('E1', Side.enemigo, column(39, 2, 3)),
      ], ScriptedDice(playerFirst));
      engine.apply(const ActivateSquad('J1'));
      final before = engine.state.squadById('J1').soldiers.first.position;
      expect(
        () => engine.apply(const MoveSquad({'J1.0': Vec2(5, 20)})),
        throwsA(isA<RuleViolation>()
            .having((v) => v.code, 'code', ViolationCode.movimientoExcesivo)),
      );
      expect(engine.state.squadById('J1').soldiers.first.position, before);
      expect(engine.state.progress!.moved, isFalse);
    });
  });

  group('moral', () {
    test('una escuadra de 5 que baja a 2 tira moral', () {
      final dice = ScriptedDice([
        ...playerFirst,
        6, 6, 6, // impactos
        6, 6, 6, // heridas
        1, 1, 1, // salvaciones fallidas
        6, 6, // moral: 12 supera MOR 7
      ]);
      final engine = engineWith([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(20, 5, 5)),
      ], dice);
      engine.apply(const ActivateSquad('J1'));
      final events = engine.apply(
          const Shoot(weaponId: 'fusil', targetSquadId: 'E1'));

      final e1 = engine.state.squadById('E1');
      expect(e1.aliveCount, 2);
      expect(events.whereType<MoraleChecked>().single.passed, isFalse);
      expect(e1.demoralized, isTrue);
      expect(dice.remaining, 0);
    });

    test('una escuadra de 5 que baja a 3 no tira moral', () {
      final dice = ScriptedDice([
        ...playerFirst,
        6, 6, 6,
        6, 6, 6,
        1, 1, 6, // dos salvaciones fallidas
      ]);
      final engine = engineWith([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(20, 5, 5)),
      ], dice);
      engine.apply(const ActivateSquad('J1'));
      final events = engine.apply(
          const Shoot(weaponId: 'fusil', targetSquadId: 'E1'));

      expect(engine.state.squadById('E1').aliveCount, 3);
      expect(events.whereType<MoraleChecked>(), isEmpty);
      expect(dice.remaining, 0);
    });
  });

  test('una escuadra Desmoralizada no cuenta para controlar objetivos', () {
    final objective = const Objective(id: 'o1', position: Vec2(22, 14));
    final enemy = squad('E1', Side.enemigo, column(24, 11, 5))
      ..demoralized = true;
    final state = BattleState(
      board: Board(objectives: [objective]),
      squads: [squad('J1', Side.jugador, column(20, 13, 2)), enemy],
    );
    expect(Battlefield(state).controllerOf(objective), Side.jugador);
  });

  test('dispersión: con 3 se desvía 3" y alcanza a quien queda a 2"', () {
    final dice = ScriptedDice([
      ...playerFirst,
      3, // precisión: falla, se desvía 3"
      1, 1, // dirección 0 grados
      6, 6, 6, // heridas; sin salvación (SAL 5 + PA 2)
      1, 1, // moral superada
    ]);
    final engine = engineWith([
      squad('J1', Side.jugador, [const Vec2(5, 14)], profile: cannonProfile),
      squad('E1', Side.enemigo, column(23, 11, 5)),
    ], dice);
    engine.apply(const ActivateSquad('J1'));
    final events = engine.apply(
        const Shoot(weaponId: 'canon', targetPoint: Vec2(20, 14)));

    final scatter = events.whereType<ScatterResolved>().single;
    expect(scatter.landed.x, closeTo(23, 1e-9));
    expect(scatter.landed.y, closeTo(14, 1e-9));
    expect(events.whereType<AttackResolved>().single.killed, 3);
    expect(engine.state.squadById('E1').aliveCount, 2);
    expect(dice.remaining, 0);
  });

  test('el cañón no puede mover y disparar', () {
    final engine = engineWith([
      squad('J1', Side.jugador, [const Vec2(5, 14)], profile: cannonProfile),
      squad('E1', Side.enemigo, column(23, 11, 5)),
    ], ScriptedDice(playerFirst));
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const MoveSquad({'J1.0': Vec2(6, 14)}));
    expect(
      () => engine.apply(
          const Shoot(weaponId: 'canon', targetPoint: Vec2(20, 14))),
      throwsA(isA<RuleViolation>()
          .having((v) => v.code, 'code', ViolationCode.movioAntesDeDisparar)),
    );
  });

  test('una carga que elimina al último enemigo termina la batalla', () {
    final engine = engineWith([
      squad('J1', Side.jugador, [const Vec2(10, 10)]),
      squad('E1', Side.enemigo, [const Vec2(13, 10)]),
    ], ScriptedDice([...playerFirst, 6, 6, 1]));
    engine.apply(const ActivateSquad('J1'));
    final events = engine.apply(const Charge(
        targetSquadId: 'E1', destinations: {'J1.0': Vec2(12, 10)}));

    expect(events.whereType<SquadDestroyed>().single.squadId, 'E1');
    expect(events.last, isA<BattleEnded>());
    expect(engine.state.step, BattleStep.terminada);
    expect(engine.state.winner, Side.jugador);
  });
}
