import 'dart:math' as math;

import 'battle_state.dart';
import 'battlefield.dart';
import 'campaign.dart';
import 'dice.dart';
import 'orders.dart';
import 'profiles.dart';
import 'setup.dart';

enum NodeKind { batalla, suministros, encuentro, fortin }

enum CampaignStatus { enCurso, victoria, derrota }

/// Batalla prevista en un nodo del mapa.
final class BattlePlan {
  const BattlePlan({
    required this.seed,
    required this.mapId,
    required this.missionId,
    required this.enemies,
    required this.requisas,
    this.rewardOrder,
  });

  factory BattlePlan.fromJson(Map<String, Object?> json) => BattlePlan(
        seed: (json['seed']! as num).toInt(),
        mapId: json['map']! as String,
        missionId: json['mission']! as String,
        enemies: (json['enemies']! as List<Object?>).cast<String>(),
        requisas: (json['requisas']! as num).toInt(),
        rewardOrder: json['order'] == null
            ? null
            : OrderType.byId(json['order']! as String),
      );

  final int seed;
  final String mapId;
  final String missionId;

  /// Perfiles de las escuadras enemigas.
  final List<String> enemies;

  /// Requisas que se ganan con la victoria.
  final int requisas;

  /// Orden que se gana con la victoria, si hay.
  final OrderType? rewardOrder;

  Map<String, Object?> toJson() => {
        'seed': seed,
        'map': mapId,
        'mission': missionId,
        'enemies': enemies,
        'requisas': requisas,
        'order': rewardOrder?.id,
      };
}

final class CampaignNode {
  const CampaignNode({
    required this.id,
    required this.kind,
    required this.depth,
    required this.x,
    required this.y,
    required this.next,
    this.battle,
    this.encounterId,
  });

  factory CampaignNode.fromJson(Map<String, Object?> json) => CampaignNode(
        id: json['id']! as String,
        kind: NodeKind.values.byName(json['kind']! as String),
        depth: (json['depth']! as num).toInt(),
        x: (json['x']! as num).toDouble(),
        y: (json['y']! as num).toDouble(),
        next: (json['next']! as List<Object?>).cast<String>(),
        battle: json['battle'] == null
            ? null
            : BattlePlan.fromJson(json['battle']! as Map<String, Object?>),
        encounterId: json['encounter'] as String?,
      );

  final String id;
  final NodeKind kind;
  final int depth;

  /// Posición en el mapa, entre 0 y 1, para la UI.
  final double x;
  final double y;
  final List<String> next;
  final BattlePlan? battle;
  final String? encounterId;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'depth': depth,
        'x': x,
        'y': y,
        'next': next,
        if (battle != null) 'battle': battle!.toJson(),
        if (encounterId != null) 'encounter': encounterId,
      };
}

/// Escuadra de la compañía. Persiste entre batallas.
final class CompanySquad {
  CompanySquad({
    required this.id,
    required this.profileId,
    required this.soldiers,
    this.experience = 0,
  });

  factory CompanySquad.fromJson(Map<String, Object?> json) => CompanySquad(
        id: json['id']! as String,
        profileId: json['profile']! as String,
        soldiers: (json['soldiers']! as num).toInt(),
        experience: (json['xp']! as num).toInt(),
      );

  final String id;
  final String profileId;
  int soldiers;
  int experience;

  Rank get rank => rankFor(experience);

  Map<String, Object?> toJson() =>
      {'id': id, 'profile': profileId, 'soldiers': soldiers, 'xp': experience};
}

/// Resultado de una escuadra de la compañía tras una batalla.
final class SquadReport {
  const SquadReport({
    required this.squadId,
    required this.profileId,
    required this.experienceGained,
    required this.rankBefore,
    required this.rankAfter,
    required this.soldiersLost,
    required this.fallen,
    required this.rested,
  });

  final String squadId;
  final String profileId;
  final int experienceGained;
  final Rank rankBefore;
  final Rank rankAfter;
  final int soldiersLost;
  final bool fallen;

  /// No fue a la batalla: descansó y recuperó un soldado si le faltaba.
  final bool rested;

  bool get promoted => rankAfter.index > rankBefore.index;
}

final class BattleReport {
  const BattleReport({
    required this.winner,
    required this.squads,
    required this.requisas,
    required this.order,
    required this.status,
  });

  final Side? winner;
  final List<SquadReport> squads;
  final int requisas;
  final OrderType? order;
  final CampaignStatus status;
}

/// Efecto de un Encuentro, leído de `data/encounters.json`.
final class EncounterEffect {
  const EncounterEffect(this.type, {this.amount = 0, this.success, this.failure});

  factory EncounterEffect.fromJson(Map<String, Object?> json) {
    List<EncounterEffect>? list(Object? v) => (v as List<Object?>?)
        ?.map((e) => EncounterEffect.fromJson(e! as Map<String, Object?>))
        .toList();
    return EncounterEffect(
      json['tipo']! as String,
      amount: (json['cantidad'] as num?)?.toInt() ?? 0,
      success: list(json['exito']),
      failure: list(json['fallo']),
    );
  }

  /// requisas, orden, curar, experiencia, bajas o azar.
  final String type;
  final int amount;

  /// Solo en "azar": efectos con 4+ en 1d6, o con 1-3.
  final List<EncounterEffect>? success;
  final List<EncounterEffect>? failure;
}

final class EncounterOption {
  const EncounterOption(this.text, this.effects);

  factory EncounterOption.fromJson(Map<String, Object?> json) => EncounterOption(
        json['texto']! as String,
        [
          for (final e in (json['efectos']! as List<Object?>))
            EncounterEffect.fromJson(e! as Map<String, Object?>),
        ],
      );

  final String text;
  final List<EncounterEffect> effects;
}

final class Encounter {
  const Encounter(this.id, this.title, this.text, this.options);

  factory Encounter.fromJson(Map<String, Object?> json) => Encounter(
        json['id']! as String,
        json['titulo']! as String,
        json['texto']! as String,
        [
          for (final o in (json['opciones']! as List<Object?>))
            EncounterOption.fromJson(o! as Map<String, Object?>),
        ],
      );

  final String id;
  final String title;
  final String text;
  final List<EncounterOption> options;

  static Map<String, Encounter> catalogFromJson(Map<String, Object?> json) => {
        for (final e in (json['encounters']! as List<Object?>)
            .cast<Map<String, Object?>>())
          e['id']! as String: Encounter.fromJson(e),
      };
}

/// Efecto ya aplicado, para mostrarlo en la UI.
typedef AppliedEffect = ({String type, int amount, String? squadId});

/// Una campaña completa: mapa, compañía y progreso. Determinista con su
/// semilla, y serializable para guardarla.
final class CampaignRun {
  CampaignRun._({
    required this.seed,
    required this.nodes,
    required this.squads,
    required this.hand,
    required this.requisas,
    this.day = 1,
    this.currentNodeId,
    Set<String>? completed,
    this.status = CampaignStatus.enCurso,
    this.nextSquadNumber = 1,
    List<String>? deployedSquadIds,
  })  : completed = completed ?? {},
        deployedSquadIds = deployedSquadIds ?? [];

  static const int maxHand = 5;
  static const int maxCompany = 8;
  static const int maxSquadsPerBattle = 4;
  static const int startingRequisas = 60;

  /// Crea una campaña nueva con su mapa generado a partir de [seed].
  factory CampaignRun.start({
    required int seed,
    required ProfileCatalog catalog,
    required List<String> encounterIds,
    int requisas = startingRequisas,
  }) {
    final dice = SeededDice(seed);
    final run = CampaignRun._(
      seed: seed,
      nodes: _generateMap(seed, dice, encounterIds),
      squads: [],
      hand: [OrderType.avanceForzado, OrderType.cuerpoATierra],
      requisas: requisas,
    );
    for (final id in const ['capitana', 'lanceros', 'tiradores', 'exploradores']) {
      run._addSquad(catalog[id]);
    }
    return run;
  }

  factory CampaignRun.fromJson(Map<String, Object?> json) => CampaignRun._(
        seed: (json['seed']! as num).toInt(),
        day: (json['day']! as num).toInt(),
        nodes: [
          for (final n
              in (json['nodes']! as List<Object?>).cast<Map<String, Object?>>())
            CampaignNode.fromJson(n),
        ],
        squads: [
          for (final s
              in (json['squads']! as List<Object?>).cast<Map<String, Object?>>())
            CompanySquad.fromJson(s),
        ],
        hand: [
          for (final o in (json['hand']! as List<Object?>))
            OrderType.byId(o! as String),
        ],
        requisas: (json['requisas']! as num).toInt(),
        currentNodeId: json['current'] as String?,
        completed: (json['completed']! as List<Object?>).cast<String>().toSet(),
        status: CampaignStatus.values.byName(json['status']! as String),
        nextSquadNumber: (json['nextSquad']! as num).toInt(),
        deployedSquadIds: (json['deployed'] as List<Object?>?)?.cast<String>(),
      );

  final int seed;
  final List<CampaignNode> nodes;
  final List<CompanySquad> squads;
  final List<OrderType> hand;
  int requisas;
  int day;
  String? currentNodeId;
  final Set<String> completed;
  CampaignStatus status;
  int nextSquadNumber;

  /// Escuadras elegidas para la batalla en curso.
  final List<String> deployedSquadIds;

  Map<String, Object?> toJson() => {
        'seed': seed,
        'day': day,
        'nodes': [for (final n in nodes) n.toJson()],
        'squads': [for (final s in squads) s.toJson()],
        'hand': [for (final o in hand) o.id],
        'requisas': requisas,
        'current': currentNodeId,
        'completed': completed.toList(),
        'status': status.name,
        'nextSquad': nextSquadNumber,
        'deployed': deployedSquadIds,
      };

  CampaignNode node(String id) => nodes.firstWhere((n) => n.id == id);

  CampaignNode? get currentNode =>
      currentNodeId == null ? null : node(currentNodeId!);

  /// Nodos a los que se puede viajar ahora.
  List<CampaignNode> get available {
    if (status != CampaignStatus.enCurso) return const [];
    final current = currentNode;
    if (current == null) return [nodes.first];
    if (!completed.contains(current.id)) return const [];
    return [for (final id in current.next) node(id)];
  }

  bool get canRecruit =>
      status == CampaignStatus.enCurso &&
      currentNode?.kind == NodeKind.suministros;

  CompanySquad squad(String id) => squads.firstWhere((s) => s.id == id);

  // -------------------------------------------------------------- viajar

  /// Viaja a [nodeId]. Los Suministros se resuelven al llegar: la compañía se
  /// recupera por completo y gana una orden si tiene hueco.
  List<AppliedEffect> travel(String nodeId, ProfileCatalog catalog) {
    final target = node(nodeId);
    if (!available.contains(target)) {
      throw StateError('No se puede viajar a $nodeId ahora.');
    }
    currentNodeId = nodeId;
    if (target.kind != NodeKind.suministros) return const [];
    final applied = <AppliedEffect>[];
    _healAll(catalog);
    applied.add((type: 'curar', amount: 0, squadId: null));
    final order = _gainOrder(_dice(1));
    if (order != null) applied.add((type: 'orden', amount: 1, squadId: null));
    _complete(target);
    return applied;
  }

  // ------------------------------------------------------------- batalla

  /// Configura la batalla del nodo actual con las escuadras elegidas.
  BattleSetup prepareBattle(List<String> squadIds, ProfileCatalog catalog) {
    final current = currentNode;
    final plan = current?.battle;
    if (current == null || plan == null || completed.contains(current.id)) {
      throw StateError('No hay batalla pendiente en el nodo actual.');
    }
    if (squadIds.isEmpty || squadIds.length > maxSquadsPerBattle) {
      throw ArgumentError('Elige entre 1 y $maxSquadsPerBattle escuadras.');
    }
    deployedSquadIds
      ..clear()
      ..addAll(squadIds);
    return BattleSetup(
      seed: plan.seed,
      mapId: plan.mapId,
      missionId: plan.missionId,
      squads: [
        for (final id in squadIds)
          SquadSetup(
            id: id,
            side: Side.jugador,
            profileId: squad(id).profileId,
            soldiers: squad(id).soldiers,
            rank: squad(id).rank,
          ),
        for (var i = 0; i < plan.enemies.length; i++)
          SquadSetup(
            id: 'enemigo_${i + 1}',
            side: Side.enemigo,
            profileId: plan.enemies[i],
            soldiers: catalog[plan.enemies[i]].soldiers,
          ),
      ],
      hands: {
        Side.jugador: List.of(hand),
        Side.enemigo: _enemyHand(current),
      },
    );
  }

  /// Aplica el resultado de una batalla terminada a la compañía.
  BattleReport finishBattle(BattleState state, ProfileCatalog catalog) {
    final current = currentNode!;
    final plan = current.battle!;
    final field = Battlefield(state);
    final reports = <SquadReport>[];

    for (final s in List.of(squads)) {
      final before = s.rank;
      if (!deployedSquadIds.contains(s.id)) {
        final max = catalog[s.profileId].soldiers;
        final rested = s.soldiers < max;
        if (rested) s.soldiers++;
        reports.add(SquadReport(
          squadId: s.id,
          profileId: s.profileId,
          experienceGained: 0,
          rankBefore: before,
          rankAfter: before,
          soldiersLost: 0,
          fallen: false,
          rested: rested,
        ));
        continue;
      }
      final battleSquad = state.squadById(s.id);
      final lost = s.soldiers - battleSquad.aliveCount;
      if (battleSquad.destroyed) {
        squads.remove(s);
        reports.add(SquadReport(
          squadId: s.id,
          profileId: s.profileId,
          experienceGained: 0,
          rankBefore: before,
          rankAfter: before,
          soldiersLost: lost,
          fallen: true,
          rested: false,
        ));
        continue;
      }
      final gained = battleExperience(battleSquad, field);
      s
        ..experience += gained
        ..soldiers = battleSquad.aliveCount;
      reports.add(SquadReport(
        squadId: s.id,
        profileId: s.profileId,
        experienceGained: gained,
        rankBefore: before,
        rankAfter: s.rank,
        soldiersLost: lost,
        fallen: false,
        rested: false,
      ));
    }

    // Las órdenes gastadas en la batalla se pierden.
    hand
      ..clear()
      ..addAll(state.hands[Side.jugador]!);

    var gainedRequisas = 0;
    OrderType? gainedOrder;
    if (state.winner == Side.jugador) {
      gainedRequisas = plan.requisas;
      requisas += gainedRequisas;
      if (plan.rewardOrder != null && hand.length < maxHand) {
        gainedOrder = plan.rewardOrder;
        hand.add(gainedOrder!);
      }
    }

    deployedSquadIds.clear();
    _complete(current);
    if (current.kind == NodeKind.fortin) {
      status = state.winner == Side.jugador
          ? CampaignStatus.victoria
          : CampaignStatus.derrota;
    }
    if (squads.isEmpty) status = CampaignStatus.derrota;

    return BattleReport(
      winner: state.winner,
      squads: reports,
      requisas: gainedRequisas,
      order: gainedOrder,
      status: status,
    );
  }

  // ---------------------------------------------------------- suministros

  /// Recluta una escuadra nueva (Recluta) en un nodo de Suministros.
  CompanySquad recruit(String profileId, ProfileCatalog catalog) {
    final profile = catalog[profileId];
    final cost = profile.cost;
    if (!canRecruit) throw StateError('Solo se recluta en Suministros.');
    if (profile.unique || cost == null) {
      throw StateError('$profileId no se puede reclutar.');
    }
    if (squads.length >= maxCompany) throw StateError('La compañía está completa.');
    if (requisas < cost) throw StateError('Requisas insuficientes.');
    requisas -= cost;
    return _addSquad(profile);
  }

  // ----------------------------------------------------------- encuentros

  /// Resuelve el Encuentro del nodo actual con la opción [optionIndex].
  List<AppliedEffect> resolveEncounter(
      Encounter encounter, int optionIndex, ProfileCatalog catalog) {
    final current = currentNode;
    if (current == null ||
        current.kind != NodeKind.encuentro ||
        completed.contains(current.id)) {
      throw StateError('No hay Encuentro pendiente.');
    }
    final dice = _dice(2);
    final applied = <AppliedEffect>[];
    for (final effect in encounter.options[optionIndex].effects) {
      _applyEffect(effect, dice, catalog, applied);
    }
    _complete(current);
    if (squads.isEmpty) status = CampaignStatus.derrota;
    return applied;
  }

  void _applyEffect(EncounterEffect effect, Dice dice, ProfileCatalog catalog,
      List<AppliedEffect> applied) {
    switch (effect.type) {
      case 'requisas':
        final before = requisas;
        requisas = math.max(0, requisas + effect.amount);
        applied.add((type: 'requisas', amount: requisas - before, squadId: null));
      case 'orden':
        if (_gainOrder(dice) != null) {
          applied.add((type: 'orden', amount: 1, squadId: null));
        }
      case 'curar':
        _healAll(catalog);
        applied.add((type: 'curar', amount: 0, squadId: null));
      case 'experiencia':
        if (squads.isEmpty) return;
        final s = squads[rollIndex(dice, squads.length)];
        s.experience += effect.amount;
        applied.add((type: 'experiencia', amount: effect.amount, squadId: s.id));
      case 'bajas':
        if (squads.isEmpty) return;
        final s = squads[rollIndex(dice, squads.length)];
        final lost = math.min(effect.amount, s.soldiers - 1);
        s.soldiers -= lost;
        applied.add((type: 'bajas', amount: lost, squadId: s.id));
      case 'azar':
        final success = dice.d6() >= 4;
        applied.add((type: success ? 'azar_exito' : 'azar_fallo', amount: 0, squadId: null));
        for (final e in (success ? effect.success : effect.failure) ?? const <EncounterEffect>[]) {
          _applyEffect(e, dice, catalog, applied);
        }
      default:
        throw FormatException('Efecto de encuentro desconocido: ${effect.type}');
    }
  }

  // ------------------------------------------------------------- apoyo

  /// Dados propios de cada operación: deterministas según semilla y día.
  Dice _dice(int salt) => SeededDice(seed * 7919 + day * 104729 + salt);

  void _complete(CampaignNode n) {
    completed.add(n.id);
    day++;
  }

  void _healAll(ProfileCatalog catalog) {
    for (final s in squads) {
      s.soldiers = catalog[s.profileId].soldiers;
    }
  }

  OrderType? _gainOrder(Dice dice) {
    if (hand.length >= maxHand) return null;
    final order = OrderType.values[rollIndex(dice, OrderType.values.length)];
    hand.add(order);
    return order;
  }

  CompanySquad _addSquad(UnitProfile profile) {
    final id = profile.unique ? profile.id : '${profile.id}_${nextSquadNumber++}';
    final s = CompanySquad(id: id, profileId: profile.id, soldiers: profile.soldiers);
    squads.add(s);
    return s;
  }

  List<OrderType> _enemyHand(CampaignNode n) => switch (n.kind) {
        NodeKind.fortin => [
            OrderType.repetid,
            OrderType.contraataque,
            OrderType.cuerpoATierra,
          ],
        _ when n.depth >= 2 => [OrderType.repetid],
        _ => [],
      };

  static const _missionMaps = {
    'dominio': 'molino',
    'defensa_vado': 'vado',
    'reconocimiento': 'llanura',
  };

  static const _enemyPool = [
    'lanceros',
    'exploradores',
    'tiradores',
    'granaderos',
    'zapadores',
    'batidores',
    'canon',
  ];

  static List<CampaignNode> _generateMap(
      int seed, Dice dice, List<String> encounterIds) {
    // Grafo fijo de 7 nodos (como en el mockup); el contenido sale de la
    // semilla.
    const layout = [
      ('n0', 0, 0.06, 0.50, ['n1', 'n2']),
      ('n1', 1, 0.27, 0.22, ['n3']),
      ('n2', 1, 0.27, 0.78, ['n3']),
      ('n3', 2, 0.50, 0.50, ['n4', 'n5']),
      ('n4', 3, 0.72, 0.22, ['n6']),
      ('n5', 3, 0.72, 0.78, ['n6']),
      ('n6', 4, 0.92, 0.50, <String>[]),
    ];

    final kinds = <String, NodeKind>{
      'n0': NodeKind.batalla,
      'n3': NodeKind.batalla,
      'n6': NodeKind.fortin,
    };
    for (final pair in const [('n1', 'n2'), ('n4', 'n5')]) {
      final support = dice.d6() <= 3 ? NodeKind.suministros : NodeKind.encuentro;
      final swap = dice.d6().isEven;
      kinds[swap ? pair.$2 : pair.$1] = support;
      kinds[swap ? pair.$1 : pair.$2] = NodeKind.batalla;
    }

    BattlePlan plan(int index, int depth, NodeKind kind) {
      if (kind == NodeKind.fortin) {
        return BattlePlan(
          seed: seed * 1000 + index,
          mapId: 'molino',
          missionId: 'dominio',
          enemies: const ['lanceros', 'granaderos', 'tiradores', 'batidores', 'canon'],
          requisas: 0,
        );
      }
      final missions = _missionMaps.keys.toList();
      final missionId = missions[rollIndex(dice, missions.length)];
      final count = depth < 2 ? 2 : 3;
      final pool = depth < 2 ? _enemyPool.take(6).toList() : _enemyPool;
      return BattlePlan(
        seed: seed * 1000 + index,
        mapId: _missionMaps[missionId]!,
        missionId: missionId,
        enemies: [for (var i = 0; i < count; i++) pool[rollIndex(dice, pool.length)]],
        requisas: 20 + 10 * depth,
        rewardOrder: dice.d6() >= 4
            ? OrderType.values[rollIndex(dice, OrderType.values.length)]
            : null,
      );
    }

    return [
      for (var i = 0; i < layout.length; i++)
        () {
          final (id, depth, x, y, next) = layout[i];
          final kind = kinds[id]!;
          final fights = kind == NodeKind.batalla || kind == NodeKind.fortin;
          return CampaignNode(
            id: id,
            kind: kind,
            depth: depth,
            x: x,
            y: y,
            next: next,
            battle: fights ? plan(i, depth, kind) : null,
            encounterId: kind == NodeKind.encuentro && encounterIds.isNotEmpty
                ? encounterIds[rollIndex(dice, encounterIds.length)]
                : null,
          );
        }(),
    ];
  }
}
