import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String file) =>
    jsonDecode(File('../../data/$file').readAsStringSync())
        as Map<String, Object?>;

final catalog = ProfileCatalog.fromJson(_json('units.json'));
final maps = MapTemplate.catalogFromJson(_json('maps.json'));
final encounters = Encounter.catalogFromJson(_json('encounters.json'));

CampaignRun newRun(int seed) => CampaignRun.start(
    seed: seed, catalog: catalog, encounterIds: encounters.keys.toList());

/// Juega la batalla del nodo actual con la IA en ambos bandos.
BattleReport playCurrentBattle(CampaignRun run) {
  final ids = run.squads.take(CampaignRun.maxSquadsPerBattle).map((s) => s.id).toList();
  final setup = run.prepareBattle(ids, catalog);
  final session =
      BattleSession.begin(setup: setup, deployedState: setup.buildState(catalog, maps));
  final state = session.engine.state;
  var guard = 0;
  while (state.step != BattleStep.terminada && guard++ < 400) {
    const SimpleAi().playActivation(session.engine, state.activeSide!);
  }
  return run.finishBattle(state, catalog);
}

void main() {
  test('los mapas cumplen lo que piden sus misiones', () {
    expect(maps.keys, containsAll(['molino', 'vado', 'llanura']));
    expect(maps['vado']!.board.objectives.single.id, 'puente');
    expect(maps['llanura']!.board.objectives, hasLength(5));
  });

  test('la misma semilla genera el mismo mapa de campaña', () {
    expect(jsonEncode(newRun(5).toJson()), jsonEncode(newRun(5).toJson()));
  });

  test('el mapa tiene batalla al inicio y fortín al final', () {
    final run = newRun(11);
    expect(run.nodes.first.kind, NodeKind.batalla);
    expect(run.nodes.last.kind, NodeKind.fortin);
    expect(run.available.single.id, 'n0');
    expect(run.squads.map((s) => s.profileId),
        ['capitana', 'lanceros', 'tiradores', 'exploradores']);
  });

  test('una batalla actualiza la compañía y abre los siguientes nodos', () {
    final run = newRun(21);
    run.travel('n0', catalog);
    final report = playCurrentBattle(run);

    expect(report.squads, hasLength(4));
    expect(run.completed, contains('n0'));
    expect(run.available.map((n) => n.id), ['n1', 'n2']);
    for (final r in report.squads.where((r) => !r.fallen)) {
      expect(r.experienceGained, greaterThanOrEqualTo(1));
    }
    expect(run.deployedSquadIds, isEmpty);
  });

  test('la campaña se guarda y se recupera igual', () {
    final run = newRun(33)..travel('n0', catalog);
    playCurrentBattle(run);
    final copy = CampaignRun.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, Object?>);
    expect(jsonEncode(copy.toJson()), jsonEncode(run.toJson()));
  });

  test('una campaña entera termina en victoria o derrota', () {
    for (var seed = 1; seed <= 8; seed++) {
      final run = newRun(seed);
      var guard = 0;
      while (run.status == CampaignStatus.enCurso && guard++ < 20) {
        final next = run.available.first;
        run.travel(next.id, catalog);
        switch (next.kind) {
          case NodeKind.batalla || NodeKind.fortin:
            playCurrentBattle(run);
          case NodeKind.encuentro:
            run.resolveEncounter(encounters[next.encounterId]!, 0, catalog);
          case NodeKind.suministros:
            break;
        }
      }
      expect(run.status, isNot(CampaignStatus.enCurso), reason: 'semilla $seed');
    }
  });

  group('suministros', () {
    CampaignRun atSupplies() {
      for (var seed = 1; seed < 100; seed++) {
        final run = newRun(seed)..travel('n0', catalog);
        playCurrentBattle(run);
        if (run.status != CampaignStatus.enCurso) continue;
        final supply = run.available
            .where((n) => n.kind == NodeKind.suministros)
            .firstOrNull;
        if (supply == null) continue;
        run.travel(supply.id, catalog);
        return run;
      }
      throw StateError('Ninguna semilla llega a Suministros.');
    }

    test('curan a toda la compañía', () {
      final run = atSupplies();
      for (final s in run.squads) {
        expect(s.soldiers, catalog[s.profileId].soldiers);
      }
      expect(run.canRecruit, isTrue);
    });

    test('se recluta pagando requisas, pero no perfiles únicos', () {
      final run = atSupplies()..requisas = 100;
      final recruit = run.recruit('granaderos', catalog);
      expect(recruit.rank, Rank.recluta);
      expect(run.requisas, 55);
      expect(() => run.recruit('capitana', catalog), throwsStateError);
    });
  });

  test('los efectos de azar aplican éxito o fallo', () {
    const effect = EncounterEffect('azar', success: [
      EncounterEffect('requisas', amount: 30),
    ], failure: [
      EncounterEffect('bajas', amount: 1),
    ]);
    // Se fuerza un nodo de encuentro para probar el efecto.
    for (var seed = 1; seed < 100; seed++) {
      final run = newRun(seed)..travel('n0', catalog);
      playCurrentBattle(run);
      final node = run.available
          .where((n) => n.kind == NodeKind.encuentro)
          .firstOrNull;
      if (node == null || run.status != CampaignStatus.enCurso) continue;
      run.travel(node.id, catalog);
      final applied = run.resolveEncounter(
          const Encounter('prueba', 't', 't', [EncounterOption('o', [effect])]),
          0,
          catalog);
      expect(applied.first.type, anyOf('azar_exito', 'azar_fallo'));
      expect(run.completed, contains(node.id));
      return;
    }
    fail('Ninguna semilla llega a un Encuentro.');
  });

  test('los rangos mejoran el perfil', () {
    final base = catalog['lanceros'];
    expect(rankedProfile(base, Rank.regular).stats.mor, base.stats.mor + 1);
    expect(rankedProfile(base, Rank.veterana).stats.pun, base.stats.pun - 1);
    expect(rankedProfile(base, Rank.elite).weapons.first.attacks,
        base.weapons.first.attacks + 1);
  });
}
