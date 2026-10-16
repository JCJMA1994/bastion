import 'ai.dart';
import 'battle_state.dart';
import 'campaign_run.dart';
import 'dice.dart';
import 'engine.dart';
import 'profiles.dart';
import 'setup.dart';

/// Resultado agregado de muchos duelos entre dos perfiles.
final class DuelStats {
  DuelStats(this.a, this.b);

  final String a;
  final String b;
  int winsA = 0;
  int winsB = 0;
  int draws = 0;

  /// Suma de la fracción de soldados que le quedan a cada bando.
  double survivalA = 0;
  double survivalB = 0;

  int get battles => winsA + winsB + draws;
  double get winRateA => battles == 0 ? 0 : winsA / battles;
  double get winRateB => battles == 0 ? 0 : winsB / battles;
}

/// Resultado agregado de muchas campañas jugadas por la IA.
final class CampaignStats {
  int runs = 0;
  int victories = 0;
  int defeats = 0;
  int unfinished = 0;
  int battles = 0;
  int battlesWon = 0;
  int fallen = 0;
  int totalDays = 0;
  final Map<String, int> defeatsByNode = {};

  double get victoryRate => runs == 0 ? 0 : victories / runs;
  double get battleWinRate => battles == 0 ? 0 : battlesWon / battles;
  double get averageDays => runs == 0 ? 0 : totalDays / runs;
}

/// Simulaciones en lote con la IA en ambos bandos, para balancear perfiles y
/// campaña. Todo es determinista con las semillas usadas.
final class Simulator {
  Simulator({
    required this.catalog,
    required this.maps,
    this.encounters = const {},
    this.ai = const SimpleAi(),
  });

  final ProfileCatalog catalog;
  final Map<String, MapTemplate> maps;
  final Map<String, Encounter> encounters;
  final SimpleAi ai;

  Dice _dice(int seed) => SeededDice(seed);

  /// Hash estable entre ejecuciones y plataformas (String.hashCode no lo es).
  static int _stableHash(String text) =>
      text.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0xFFFF);

  /// Juega una batalla con la IA en ambos bandos hasta el final.
  void playOut(BattleEngine engine, {int maxActivations = 400}) {
    final state = engine.state;
    var guard = 0;
    while (state.step != BattleStep.terminada && guard++ < maxActivations) {
      ai.playActivation(engine, state.activeSide!);
    }
  }

  /// [battles] duelos de dos escuadras de [a] contra dos de [b] en el mapa
  /// [mapId] sin objetivos: gana quien elimina al otro o quien conserva más
  /// soldados al final de la ronda 5. Los bandos se alternan para compensar
  /// la ventaja de lado.
  DuelStats duel(String a, String b, {int battles = 100, String mapId = 'molino'}) {
    final template = maps[mapId]!;
    final duelMaps = {
      'duelo': MapTemplate(
        id: 'duelo',
        name: 'Duelo',
        missionId: 'dominio',
        board: Board(
          width: template.board.width,
          height: template.board.height,
          terrain: template.board.terrain,
        ),
      ),
    };
    final stats = DuelStats(a, b);
    for (var i = 0; i < battles; i++) {
      final aIsPlayer = i.isEven;
      final sideA = aIsPlayer ? Side.jugador : Side.enemigo;
      final sideB = sideA.opponent;
      SquadSetup squad(String id, Side side, String profile) => SquadSetup(
          id: id,
          side: side,
          profileId: profile,
          soldiers: catalog[profile].soldiers);
      final setup = BattleSetup(
        seed: 10007 * (i + 1) + _stableHash(a) * 31 + _stableHash(b),
        mapId: 'duelo',
        missionId: 'dominio',
        squads: [
          squad('a1', sideA, a),
          squad('a2', sideA, a),
          squad('b1', sideB, b),
          squad('b2', sideB, b),
        ],
      );
      final state = setup.buildState(catalog, duelMaps);
      final engine = BattleEngine(state: state, dice: _dice(setup.seed));
      engine.start();
      playOut(engine);

      double survival(String id1, String id2) {
        final s1 = state.squadById(id1);
        final s2 = state.squadById(id2);
        return (s1.aliveCount + s2.aliveCount) /
            (s1.startingCount + s2.startingCount);
      }

      final sa = survival('a1', 'a2');
      final sb = survival('b1', 'b2');
      stats
        ..survivalA += sa
        ..survivalB += sb;
      final winner = state.winner ??
          (sa > sb ? sideA : (sb > sa ? sideB : null));
      if (winner == sideA) {
        stats.winsA++;
      } else if (winner == sideB) {
        stats.winsB++;
      } else {
        stats.draws++;
      }
    }
    return stats;
  }

  /// Todos contra todos entre [profiles].
  List<DuelStats> roundRobin(List<String> profiles, {int battles = 100}) => [
        for (var i = 0; i < profiles.length; i++)
          for (var j = i + 1; j < profiles.length; j++)
            duel(profiles[i], profiles[j], battles: battles),
      ];

  /// [runs] campañas completas: la IA elige el primer nodo disponible, lleva
  /// a las 4 primeras escuadras, recluta la más barata que pueda pagar y
  /// elige siempre la primera opción de los Encuentros.
  CampaignStats campaigns({int runs = 50, int firstSeed = 1}) {
    final stats = CampaignStats();
    for (var seed = firstSeed; seed < firstSeed + runs; seed++) {
      final run = CampaignRun.start(
          seed: seed, catalog: catalog, encounterIds: encounters.keys.toList());
      var guard = 0;
      while (run.status == CampaignStatus.enCurso && guard++ < 30) {
        final next = run.available.firstOrNull;
        if (next == null) break;
        run.travel(next.id, catalog);
        switch (next.kind) {
          case NodeKind.batalla || NodeKind.fortin:
            final ids = run.squads
                .take(CampaignRun.maxSquadsPerBattle)
                .map((s) => s.id)
                .toList();
            final setup = run.prepareBattle(ids, catalog);
            final state = setup.buildState(catalog, maps);
            final engine = BattleEngine(state: state, dice: _dice(setup.seed));
            engine.start();
            playOut(engine);
            final report = run.finishBattle(state, catalog);
            stats.battles++;
            if (report.winner == Side.jugador) stats.battlesWon++;
            stats.fallen += report.squads.where((r) => r.fallen).length;
            if (run.status == CampaignStatus.derrota) {
              stats.defeatsByNode[next.id] =
                  (stats.defeatsByNode[next.id] ?? 0) + 1;
            }
          case NodeKind.encuentro:
            final encounter = encounters[next.encounterId];
            if (encounter != null) run.resolveEncounter(encounter, 0, catalog);
          case NodeKind.suministros:
            final options = catalog.all
                .where((p) => !p.unique && p.cost != null && p.cost! <= run.requisas)
                .toList()
              ..sort((x, y) => x.cost!.compareTo(y.cost!));
            if (options.isNotEmpty && run.squads.length < CampaignRun.maxCompany) {
              run.recruit(options.first.id, catalog);
            }
        }
      }
      stats
        ..runs++
        ..totalDays += run.day;
      switch (run.status) {
        case CampaignStatus.victoria:
          stats.victories++;
        case CampaignStatus.derrota:
          stats.defeats++;
        case CampaignStatus.enCurso:
          stats.unfinished++;
      }
    }
    return stats;
  }
}
