import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String file) =>
    jsonDecode(File('../../data/$file').readAsStringSync())
        as Map<String, Object?>;

void main() {
  final simulator = Simulator(
    catalog: ProfileCatalog.fromJson(_json('units.json')),
    maps: MapTemplate.catalogFromJson(_json('maps.json')),
    encounters: Encounter.catalogFromJson(_json('encounters.json')),
  );

  test('un duelo cuenta todas las batallas y es determinista', () {
    final a = simulator.duel('lanceros', 'granaderos', battles: 6);
    final b = simulator.duel('lanceros', 'granaderos', battles: 6);
    expect(a.battles, 6);
    expect([a.winsA, a.winsB, a.draws], [b.winsA, b.winsB, b.draws]);
  });

  test('las campañas simuladas terminan', () {
    final stats = simulator.campaigns(runs: 4);
    expect(stats.runs, 4);
    expect(stats.unfinished, 0);
    expect(stats.battles, greaterThan(0));
  });

  test('la IA sin órdenes no gasta PM en órdenes', () {
    final sim = Simulator(
      catalog: simulator.catalog,
      maps: simulator.maps,
      encounters: simulator.encounters,
      ai: const SimpleAi(useOrders: false),
    );
    final setup = BattleSetup(
      seed: 3,
      mapId: 'molino',
      missionId: 'dominio',
      squads: const [
        SquadSetup(id: 'j', side: Side.jugador, profileId: 'lanceros', soldiers: 5),
        SquadSetup(id: 'e', side: Side.enemigo, profileId: 'granaderos', soldiers: 4),
      ],
      hands: {
        for (final side in Side.values) side: OrderType.values.toList(),
      },
    );
    final engine =
        BattleEngine(state: setup.buildState(sim.catalog, sim.maps), dice: SeededDice(3))
          ..start();
    sim.playOut(engine);
    expect(engine.history.whereType<PlayOrder>(), isEmpty);
    expect(engine.state.hands[Side.jugador], hasLength(OrderType.values.length));
  });
}
