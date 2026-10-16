import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String file) =>
    jsonDecode(File('../../data/$file').readAsStringSync())
        as Map<String, Object?>;

final catalog = ProfileCatalog.fromJson(_json('units.json'));
final maps = MapTemplate.catalogFromJson(_json('maps.json'));

BattleSetup demoSetup() => const BattleSetup(
      seed: 77,
      mapId: 'molino',
      missionId: 'dominio',
      squads: [
        SquadSetup(id: 'j1', side: Side.jugador, profileId: 'lanceros', soldiers: 5),
        SquadSetup(id: 'j2', side: Side.jugador, profileId: 'tiradores', soldiers: 4),
        SquadSetup(id: 'e1', side: Side.enemigo, profileId: 'granaderos', soldiers: 4),
        SquadSetup(id: 'e2', side: Side.enemigo, profileId: 'lanceros', soldiers: 5),
      ],
      hands: {
        Side.jugador: [OrderType.repetid],
      },
    );

void main() {
  test('el despliegue automático deja cada escuadra en su zona', () {
    final state = demoSetup().buildState(catalog, maps);
    expect(Battlefield(state).invalidDeployments(), isEmpty);
    expect(state.squadById('j2').aliveCount, 4);
  });

  test('colocar fuera de la zona se rechaza', () {
    final state = demoSetup().buildState(catalog, maps);
    final deployment = Deployment(state);
    expect(
      () => deployment.place(state.squadById('j1'), const Vec2(20, 14)),
      throwsA(isA<RuleViolation>()
          .having((v) => v.code, 'code', ViolationCode.fueraDeZona)),
    );
    deployment.place(state.squadById('j1'), const Vec2(4, 3));
    expect(Battlefield(state).invalidDeployments(), isEmpty);
  });

  test('los comandos sobreviven a JSON', () {
    const commands = <Command>[
      ActivateSquad('a'),
      MoveSquad({'a.0': Vec2(1, 2)}, upperFloor: true),
      Shoot(weaponId: 'w', targetSquadId: 'b'),
      Shoot(weaponId: 'canon', targetPoint: Vec2(3, 4)),
      Charge(targetSquadId: 'b', destinations: {'a.0': Vec2(5, 6)}),
      Fight('b'),
      Secure(),
      Entrench(),
      Run({'a.1': Vec2(7, 8)}),
      EndActivation(),
      PlayOrder(OrderType.arenga, targetSquadId: 'c'),
      Fortify(Vec2(9, 10), vertical: true),
    ];
    for (final c in commands) {
      final copy = Command.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
      expect(jsonEncode(copy.toJson()), jsonEncode(c.toJson()));
    }
  });

  test('una sesión guardada a mitad de batalla se recupera idéntica', () {
    final setup = demoSetup();
    final session =
        BattleSession.begin(setup: setup, deployedState: setup.buildState(catalog, maps));
    final state = session.engine.state;
    for (var i = 0; i < 5 && state.step != BattleStep.terminada; i++) {
      const SimpleAi().playActivation(session.engine, state.activeSide!);
    }
    final saved = jsonDecode(jsonEncode(session.toJson())) as Map<String, Object?>;
    final restored = BattleSession.restore(saved, catalog, maps);

    String snapshot(BattleState s) => jsonEncode({
          'round': s.round,
          'active': s.activeSide?.name,
          'pv': {for (final e in s.victoryPoints.entries) e.key.name: e.value},
          'squads': [
            for (final q in s.squads)
              [q.id, q.aliveCount, q.demoralized, for (final p in q.soldiers) p.position.toJson()],
          ],
        });
    expect(snapshot(restored.engine.state), snapshot(state));
  });

  test('la decoración de maps.json no cambia el tablero del motor', () {
    final raw = _json('maps.json');
    final stripped = jsonDecode(jsonEncode(raw)) as Map<String, Object?>;
    for (final map in (stripped['maps']! as List).cast<Map<String, Object?>>()) {
      for (final area in (map['terreno']! as List).cast<Map<String, Object?>>()) {
        area.remove('decoracion');
      }
    }
    final a = MapTemplate.catalogFromJson(raw);
    final b = MapTemplate.catalogFromJson(stripped);
    for (final id in a.keys) {
      final ta = a[id]!.board.terrain, tb = b[id]!.board.terrain;
      expect(ta.length, tb.length);
      for (var i = 0; i < ta.length; i++) {
        expect(ta[i].polygon.points, tb[i].polygon.points);
        expect(ta[i].type, tb[i].type);
        expect(ta[i].hasFloor, tb[i].hasFloor);
      }
    }
  });
}
