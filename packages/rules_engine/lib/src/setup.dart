import 'battle_state.dart';
import 'campaign.dart';
import 'commands.dart';
import 'deployment.dart';
import 'dice.dart';
import 'engine.dart';
import 'events.dart';
import 'geometry.dart';
import 'missions.dart';
import 'orders.dart';
import 'profiles.dart';

/// Plantilla de tablero de `data/maps.json`.
final class MapTemplate {
  const MapTemplate({
    required this.id,
    required this.name,
    required this.missionId,
    required this.board,
  });

  factory MapTemplate.fromJson(Map<String, Object?> json) {
    double n(Object? v) => (v! as num).toDouble();
    return MapTemplate(
      id: json['id']! as String,
      name: json['nombre']! as String,
      missionId: json['mision']! as String,
      board: Board(
        width: n(json['ancho']),
        height: n(json['alto']),
        terrain: [
          for (final t in (json['terreno']! as List<Object?>)
              .cast<Map<String, Object?>>())
            TerrainArea(
              id: t['id']! as String,
              type: TerrainType.values.byName(t['tipo']! as String),
              polygon: () {
                final r = (t['rect']! as List<Object?>).map(n).toList();
                return Polygon.rect(r[0], r[1], r[2], r[3]);
              }(),
              hasFloor: (t['piso'] as bool?) ?? false,
            ),
        ],
        objectives: [
          for (final o in (json['objetivos']! as List<Object?>)
              .cast<Map<String, Object?>>())
            Objective(
              id: o['id']! as String,
              position: Vec2(n(o['x']), n(o['y'])),
              value: (o['valor'] as num?)?.toInt() ?? 1,
            ),
        ],
      ),
    );
  }

  final String id;
  final String name;
  final String missionId;
  final Board board;

  static Map<String, MapTemplate> catalogFromJson(Map<String, Object?> json) => {
        for (final m in (json['maps']! as List<Object?>)
            .cast<Map<String, Object?>>())
          m['id']! as String: MapTemplate.fromJson(m),
      };
}

/// Crea la misión de [id]. En Defensa del vado defiende [defender].
Mission missionFromId(String id, {Side defender = Side.jugador}) =>
    switch (id) {
      'dominio' => Dominio(),
      'defensa_vado' => DefensaDelVado(defender: defender),
      'reconocimiento' => Reconocimiento(),
      _ => throw ArgumentError.value(id, 'id', 'Misión desconocida'),
    };

/// Escuadra que entra en una batalla.
final class SquadSetup {
  const SquadSetup({
    required this.id,
    required this.side,
    required this.profileId,
    required this.soldiers,
    this.rank = Rank.recluta,
    this.positions,
  });

  factory SquadSetup.fromJson(Map<String, Object?> json) => SquadSetup(
        id: json['id']! as String,
        side: Side.values.byName(json['side']! as String),
        profileId: json['profile']! as String,
        soldiers: (json['soldiers']! as num).toInt(),
        rank: Rank.values.byName((json['rank'] as String?) ?? 'recluta'),
        positions: (json['positions'] as List<Object?>?)
            ?.map((p) => Vec2.fromJson(p! as Map<String, Object?>))
            .toList(),
      );

  final String id;
  final Side side;
  final String profileId;
  final int soldiers;
  final Rank rank;

  /// Nulo antes del despliegue.
  final List<Vec2>? positions;

  Map<String, Object?> toJson() => {
        'id': id,
        'side': side.name,
        'profile': profileId,
        'soldiers': soldiers,
        'rank': rank.name,
        if (positions != null)
          'positions': [for (final p in positions!) p.toJson()],
      };
}

/// Todo lo necesario para reconstruir una batalla: con la misma
/// configuración y los mismos comandos, el resultado es idéntico.
final class BattleSetup {
  const BattleSetup({
    required this.seed,
    required this.mapId,
    required this.missionId,
    required this.squads,
    this.defender = Side.jugador,
    this.hands = const {},
  });

  factory BattleSetup.fromJson(Map<String, Object?> json) => BattleSetup(
        seed: (json['seed']! as num).toInt(),
        mapId: json['map']! as String,
        missionId: json['mission']! as String,
        defender: Side.values.byName((json['defender'] as String?) ?? 'jugador'),
        squads: [
          for (final s in (json['squads']! as List<Object?>)
              .cast<Map<String, Object?>>())
            SquadSetup.fromJson(s),
        ],
        hands: {
          for (final e in ((json['hands'] as Map<String, Object?>?) ?? const {})
              .entries)
            Side.values.byName(e.key): [
              for (final id in (e.value! as List<Object?>))
                OrderType.byId(id! as String),
            ],
        },
      );

  final int seed;
  final String mapId;
  final String missionId;
  final Side defender;
  final List<SquadSetup> squads;
  final Map<Side, List<OrderType>> hands;

  Map<String, Object?> toJson() => {
        'seed': seed,
        'map': mapId,
        'mission': missionId,
        'defender': defender.name,
        'squads': [for (final s in squads) s.toJson()],
        'hands': {
          for (final e in hands.entries)
            e.key.name: [for (final o in e.value) o.id],
        },
      };

  /// Estado inicial. Las escuadras sin posiciones se despliegan solas.
  BattleState buildState(
      ProfileCatalog catalog, Map<String, MapTemplate> maps) {
    final template = maps[mapId] ??
        (throw ArgumentError.value(mapId, 'mapId', 'Mapa desconocido'));
    final state = BattleState(
      board: template.board,
      mission: missionFromId(missionId, defender: defender),
      hands: hands,
      squads: [
        for (final s in squads)
          Squad.deploy(
            id: s.id,
            side: s.side,
            profile: rankedProfile(catalog[s.profileId], s.rank),
            positions: s.positions ??
                [for (var i = 0; i < s.soldiers; i++) const Vec2(-100, -100)],
          ),
      ],
    );
    final deployment = Deployment(state);
    for (final side in Side.values) {
      final pending = squads.any((s) => s.side == side && s.positions == null);
      if (pending) deployment.autoDeploy(side);
    }
    return state;
  }

  /// Copia con las posiciones actuales de [state] (tras el despliegue).
  BattleSetup withPositionsFrom(BattleState state) => BattleSetup(
        seed: seed,
        mapId: mapId,
        missionId: missionId,
        defender: defender,
        hands: hands,
        squads: [
          for (final s in squads)
            SquadSetup(
              id: s.id,
              side: s.side,
              profileId: s.profileId,
              soldiers: s.soldiers,
              rank: s.rank,
              positions: [
                for (final soldier in state.squadById(s.id).soldiers)
                  soldier.position,
              ],
            ),
        ],
      );
}

/// Batalla guardable: configuración desplegada + comandos aplicados.
final class BattleSession {
  BattleSession._(this.setup, this.engine);

  /// Empieza una batalla ya desplegada.
  factory BattleSession.begin({
    required BattleSetup setup,
    required BattleState deployedState,
  }) {
    final frozen = setup.withPositionsFrom(deployedState);
    final engine =
        BattleEngine(state: deployedState, dice: SeededDice(frozen.seed));
    final session = BattleSession._(frozen, engine);
    session.startEvents = engine.start();
    return session;
  }

  /// Reconstruye una batalla guardada rejugando sus comandos.
  factory BattleSession.restore(Map<String, Object?> json,
      ProfileCatalog catalog, Map<String, MapTemplate> maps) {
    final setup =
        BattleSetup.fromJson(json['setup']! as Map<String, Object?>);
    final engine = BattleEngine(
        state: setup.buildState(catalog, maps), dice: SeededDice(setup.seed));
    final session = BattleSession._(setup, engine);
    session.startEvents = engine.start();
    for (final c
        in (json['commands']! as List<Object?>).cast<Map<String, Object?>>()) {
      engine.apply(Command.fromJson(c));
    }
    return session;
  }

  final BattleSetup setup;
  final BattleEngine engine;
  List<GameEvent> startEvents = const [];

  Map<String, Object?> toJson() => {
        'setup': setup.toJson(),
        'commands': [for (final c in engine.history) c.toJson()],
      };
}
