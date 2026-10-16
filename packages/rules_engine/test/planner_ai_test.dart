import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('Planner.charge llega al contacto y el motor acepta la carga', () {
    final engine = BattleEngine(
      state: BattleState(board: const Board(), squads: [
        squad('J1', Side.jugador, column(10, 10, 3)),
        squad('E1', Side.enemigo, column(14, 10, 3)),
      ]),
      dice: SeededDice(7),
    )..start();
    final state = engine.state;
    if (state.activeSide == Side.enemigo) {
      engine
        ..apply(const ActivateSquad('E1'))
        ..apply(const EndActivation());
    }
    final j1 = state.squadById('J1');
    final plan = Planner.charge(state, j1, state.squadById('E1'),
        distance: BattleEngine.chargeDistance);
    expect(plan, isNotNull);

    engine.apply(const ActivateSquad('J1'));
    final events =
        engine.apply(Charge(targetSquadId: 'E1', destinations: plan!));
    expect(events.whereType<ChargeMade>(), hasLength(1));
  });

  test('la IA termina batallas completas sin bloquearse', () {
    final catalog = ProfileCatalog.fromJson(
        jsonDecode(File('../../data/units.json').readAsStringSync())
            as Map<String, Object?>);
    List<Vec2> block(double x, double y, int n) => [
          for (var i = 0; i < n; i++) Vec2(x + (i % 3) * 1.5, y + (i ~/ 3) * 1.5),
        ];

    for (var seed = 1; seed <= 25; seed++) {
      final state = BattleState(
        board: Board(
          terrain: [
            TerrainArea(
                id: 'ruinas',
                type: TerrainType.ruinas,
                polygon: Polygon.rect(18, 4, 8, 6),
                hasFloor: true),
            TerrainArea(
                id: 'bosque',
                type: TerrainType.bosque,
                polygon: Polygon.rect(18, 18, 8, 5)),
          ],
          objectives: standardObjectives,
        ),
        squads: [
          Squad.deploy(id: 'j_cap', side: Side.jugador,
              profile: catalog['capitana'], positions: [const Vec2(4, 14)]),
          Squad.deploy(id: 'j_lan', side: Side.jugador,
              profile: catalog['lanceros'], positions: block(2, 4, 5)),
          Squad.deploy(id: 'j_gra', side: Side.jugador,
              profile: catalog['granaderos'], positions: block(2, 18, 4)),
          Squad.deploy(id: 'j_can', side: Side.jugador,
              profile: catalog['canon'], positions: [const Vec2(3, 24)]),
          Squad.deploy(id: 'e_bat', side: Side.enemigo,
              profile: catalog['batidores'], positions: block(37, 4, 3)),
          Squad.deploy(id: 'e_tir', side: Side.enemigo,
              profile: catalog['tiradores'], positions: block(37, 12, 5)),
          Squad.deploy(id: 'e_zap', side: Side.enemigo,
              profile: catalog['zapadores'], positions: block(37, 20, 3)),
        ],
        hands: {
          for (final side in Side.values) side: OrderType.values.toList(),
        },
      );
      final engine = BattleEngine(state: state, dice: SeededDice(seed))..start();
      expect(Battlefield(state).invalidDeployments(), isEmpty);

      const ai = SimpleAi();
      var guard = 0;
      while (state.step != BattleStep.terminada && guard++ < 400) {
        ai.playActivation(engine, state.activeSide!);
        expect(state.activeSquadId, isNull,
            reason: 'semilla $seed: la IA dejó una activación abierta');
      }
      expect(state.step, BattleStep.terminada, reason: 'semilla $seed');
    }
  });
}
