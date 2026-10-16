import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('data/orders.json coincide con OrderType', () {
    final json = jsonDecode(File('../../data/orders.json').readAsStringSync())
        as Map<String, Object?>;
    final orders = (json['orders']! as List<Object?>).cast<Map<String, Object?>>();
    expect(orders, hasLength(OrderType.values.length));
    for (final o in orders) {
      expect(OrderType.byId(o['id']! as String).cost, o['pm']);
    }
  });

  group('Avance forzado', () {
    test('permite mover 9" y se gasta', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(39, 5, 3)),
      ], ScriptedDice(playerFirst), hands: {
        Side.jugador: [OrderType.avanceForzado],
      });
      final j1 = engine.state.squadById('J1');
      engine
        ..apply(const ActivateSquad('J1'))
        ..apply(const PlayOrder(OrderType.avanceForzado))
        ..apply(MoveSquad(Planner.translate(j1, const Vec2(9, 0))));

      expect(j1.soldiers.first.position.x, closeTo(14, 1e-9));
      expect(engine.state.commandPoints[Side.jugador], 2);
      expect(engine.state.hands[Side.jugador], isEmpty);
    });

    test('sin la orden, 9" es demasiado', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(5, 5, 3)),
        squad('E1', Side.enemigo, column(39, 5, 3)),
      ], ScriptedDice(playerFirst));
      final j1 = engine.state.squadById('J1');
      engine.apply(const ActivateSquad('J1'));
      expect(
        () => engine.apply(MoveSquad(Planner.translate(j1, const Vec2(9, 0)))),
        throwsA(isA<RuleViolation>()
            .having((v) => v.code, 'code', ViolationCode.movimientoExcesivo)),
      );
    });
  });

  test('sin PM suficientes no se puede jugar', () {
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 5, 3)),
      squad('E1', Side.enemigo, column(39, 5, 3)),
    ], ScriptedDice(playerFirst), hands: {
      Side.jugador: [OrderType.doblePaso, OrderType.contraataque],
    });
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const PlayOrder(OrderType.doblePaso)); // 3 PM - 2 = 1
    expect(
      () => engine.apply(
          const PlayOrder(OrderType.contraataque, targetSquadId: 'J1')),
      throwsA(isA<RuleViolation>().having(
          (v) => v.code, 'code', ViolationCode.puntosDeMandoInsuficientes)),
    );
  });

  test('¡Repetid! repite el primer dado de impactar fallido', () {
    final dice = ScriptedDice([
      ...playerFirst,
      1, 6, // falla y repite: impacta
      6, 6, // impactan
      1, 1, 1, // ninguna hiere
    ]);
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 5, 3)),
      squad('E1', Side.enemigo, column(20, 5, 3)),
    ], dice, hands: {
      Side.jugador: [OrderType.repetid],
    });
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const PlayOrder(OrderType.repetid));
    final events =
        engine.apply(const Shoot(weaponId: 'fusil', targetSquadId: 'E1'));
    expect(events.whereType<AttackResolved>().single.hits, 3);
    expect(dice.remaining, 0);
  });

  test('Cuerpo a tierra da +1 a la salvación y se consume', () {
    final dice = ScriptedDice([
      ...playerFirst,
      6, 6, 6, // impactos del enemigo
      6, 6, 6, // heridas
      4, 4, 4, // salvan con 4+ gracias a la orden (sin ella, 5+)
    ]);
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 2, 3)),
      squad('J2', Side.jugador, column(5, 15, 3)),
      squad('E1', Side.enemigo, column(19, 15, 3)),
    ], dice, hands: {
      Side.jugador: [OrderType.cuerpoATierra],
    });
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const PlayOrder(OrderType.cuerpoATierra, targetSquadId: 'J2'))
      ..apply(const EndActivation())
      ..apply(const ActivateSquad('E1'))
      ..apply(const Shoot(weaponId: 'fusil', targetSquadId: 'J2'));

    final j2 = engine.state.squadById('J2');
    expect(j2.aliveCount, 3);
    expect(j2.takingCover, isFalse);
    expect(dice.remaining, 0);
  });

  test('Contraataque: la escuadra cargada golpea primero', () {
    final engine = startBattle([
      squad('J1', Side.jugador, [const Vec2(10, 10)]),
      squad('E1', Side.enemigo, [const Vec2(13, 10)]),
    ], ScriptedDice([...playerFirst, 6, 6, 1]), hands: {
      Side.jugador: [OrderType.contraataque],
    });
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const PlayOrder(OrderType.contraataque, targetSquadId: 'J1'))
      ..apply(const EndActivation())
      ..apply(const ActivateSquad('E1'));
    final events = engine.apply(const Charge(
        targetSquadId: 'J1', destinations: {'E1.0': Vec2(11, 10)}));

    expect(events.whereType<AttackResolved>().first.attackerId, 'J1');
    expect(engine.state.winner, Side.jugador);
  });

  test('Doble paso: el mismo bando activa otra escuadra', () {
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 2, 3)),
      squad('J2', Side.jugador, column(5, 15, 3)),
      squad('E1', Side.enemigo, column(39, 5, 3)),
    ], ScriptedDice(playerFirst), hands: {
      Side.jugador: [OrderType.doblePaso],
    });
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const PlayOrder(OrderType.doblePaso))
      ..apply(const EndActivation());
    expect(engine.state.activeSide, Side.jugador);
    expect(() => engine.apply(const ActivateSquad('J2')), returnsNormally);
  });

  test('Fuego de cobertura quita 2" de MOV en la próxima activación', () {
    final dice = ScriptedDice([
      ...playerFirst,
      6, 1, 1, // 1 impacto
      1, // no hiere
      ...playerFirst, // iniciativa de la ronda 2
    ]);
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 5, 3)),
      squad('E1', Side.enemigo, column(20, 5, 3)),
    ], dice, hands: {
      Side.jugador: [OrderType.fuegoCobertura],
    });
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const PlayOrder(OrderType.fuegoCobertura))
      ..apply(const Shoot(weaponId: 'fusil', targetSquadId: 'E1'))
      ..apply(const ActivateSquad('E1'));

    final e1 = engine.state.squadById('E1');
    expect(e1.suppressed, isTrue);
    expect(
      () => engine.apply(MoveSquad(Planner.translate(e1, const Vec2(6, 0)))),
      throwsA(isA<RuleViolation>()),
    );
    engine
      ..apply(MoveSquad(Planner.translate(e1, const Vec2(4, 0))))
      ..apply(const EndActivation());
    expect(e1.suppressed, isFalse);
  });

  test('Fuego concentrado: +1 a herir contra una escuadra ya disparada', () {
    final dice = ScriptedDice([
      ...playerFirst,
      1, 1, 1, // J1 falla todo, pero E1 queda marcada
      6, 6, 6, // J2 impacta
      3, 3, 3, // hieren con 3+ gracias a la orden
      6, 6, 6, // salvan
      ...playerFirst, // iniciativa de la ronda 2
    ]);
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 2, 3)),
      squad('J2', Side.jugador, column(5, 12, 3)),
      squad('E1', Side.enemigo, column(19, 8, 3)),
    ], dice, hands: {
      Side.jugador: [OrderType.fuegoConcentrado],
    });
    engine
      ..apply(const ActivateSquad('J1'))
      ..apply(const Shoot(weaponId: 'fusil', targetSquadId: 'E1'))
      ..apply(const ActivateSquad('E1'))
      ..apply(const EndActivation())
      ..apply(const ActivateSquad('J2'))
      ..apply(const PlayOrder(OrderType.fuegoConcentrado));
    final events =
        engine.apply(const Shoot(weaponId: 'fusil', targetSquadId: 'E1'));
    expect(events.whereType<AttackResolved>().single.wounds, 3);
    expect(dice.remaining, 0);
  });

  test('Arenga solo sirve con una escuadra Desmoralizada', () {
    final engine = startBattle([
      squad('J1', Side.jugador, column(5, 2, 3)),
      squad('J2', Side.jugador, column(5, 15, 3)),
      squad('E1', Side.enemigo, column(39, 5, 3)),
    ], ScriptedDice(playerFirst), hands: {
      Side.jugador: [OrderType.arenga],
    });
    final j2 = engine.state.squadById('J2')..demoralized = true;
    engine.apply(const ActivateSquad('J1'));
    expect(
      () => engine
          .apply(const PlayOrder(OrderType.arenga, targetSquadId: 'J1')),
      throwsA(isA<RuleViolation>()
          .having((v) => v.code, 'code', ViolationCode.ordenSinObjetivo)),
    );
    engine.apply(const PlayOrder(OrderType.arenga, targetSquadId: 'J2'));
    expect(j2.demoralized, isFalse);
  });

  group('Fortificar', () {
    test('Zapadores colocan un parapeto que da cobertura', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(10, 10, 3), profile: sapperProfile),
        squad('E1', Side.enemigo, column(30, 10, 3)),
      ], ScriptedDice(playerFirst));
      engine.apply(const ActivateSquad('J1'));
      final events =
          engine.apply(const Fortify(Vec2(12, 11.5), vertical: true));

      expect(events.whereType<Fortified>(), hasLength(1));
      expect(engine.state.fortifications.single.type, TerrainType.muroBajo);
      expect(
          engine.field.inCover(
              engine.state.squadById('E1'), engine.state.squadById('J1')),
          isTrue);
    });

    test('otras escuadras no pueden fortificar', () {
      final engine = startBattle([
        squad('J1', Side.jugador, column(10, 10, 3)),
        squad('E1', Side.enemigo, column(30, 10, 3)),
      ], ScriptedDice(playerFirst));
      engine.apply(const ActivateSquad('J1'));
      expect(
        () => engine.apply(const Fortify(Vec2(12, 11.5))),
        throwsA(isA<RuleViolation>()
            .having((v) => v.code, 'code', ViolationCode.sinHabilidad)),
      );
    });
  });
}
