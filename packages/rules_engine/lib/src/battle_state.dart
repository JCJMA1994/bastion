import 'geometry.dart';
import 'missions.dart';
import 'orders.dart';
import 'profiles.dart';

enum Side {
  jugador,
  enemigo;

  Side get opponent => this == jugador ? enemigo : jugador;
}

/// Pasos de la ronda.
enum BattleStep { mando, activaciones, puntuacion, terminada }

enum TerrainType { ruinas, bosque, crater, muroBajo }

final class TerrainArea {
  const TerrainArea({
    required this.id,
    required this.type,
    required this.polygon,
    this.hasFloor = false,
  });

  final String id;
  final TerrainType type;
  final Polygon polygon;

  /// Solo ruinas: tiene un piso alto donde se puede estar elevado.
  final bool hasFloor;
}

final class Objective {
  const Objective({required this.id, required this.position, this.value = 1});

  /// Radio del marcador (1" de diámetro).
  static const double radius = 0.5;

  final String id;
  final Vec2 position;

  /// PV que da en cada paso de Puntuación.
  final int value;
}

final class Board {
  const Board({
    this.width = 44,
    this.height = 28,
    this.terrain = const [],
    this.objectives = const [],
  });

  final double width;
  final double height;
  final List<TerrainArea> terrain;
  final List<Objective> objectives;
}

final class Soldier {
  Soldier({
    required this.id,
    required this.position,
    required this.wounds,
    this.baseRadius = 0.5,
  });

  final String id;
  Vec2 position;

  /// Heridas que le quedan.
  int wounds;

  /// Radio de la peana en pulgadas.
  final double baseRadius;

  bool get alive => wounds > 0;
  Disc get disc => (center: position, radius: baseRadius);
}

final class Squad {
  Squad({
    required this.id,
    required this.side,
    required this.profile,
    required this.soldiers,
  }) : startingCount = soldiers.length;

  /// Crea una escuadra con todos sus soldados en las posiciones dadas.
  factory Squad.deploy({
    required String id,
    required Side side,
    required UnitProfile profile,
    required List<Vec2> positions,
    double baseRadius = 0.5,
  }) =>
      Squad(
        id: id,
        side: side,
        profile: profile,
        soldiers: [
          for (var i = 0; i < positions.length; i++)
            Soldier(
              id: '$id.$i',
              position: positions[i],
              wounds: profile.stats.her,
              baseRadius: baseRadius,
            ),
        ],
      );

  final String id;
  final Side side;
  final UnitProfile profile;
  final List<Soldier> soldiers;

  /// Soldados con los que empezó la batalla.
  final int startingCount;

  bool demoralized = false;
  bool activatedThisRound = false;
  bool upperFloor = false;
  bool entrenched = false;
  bool securing = false;

  /// Orden Cuerpo a tierra preparada: +1 a la salvación contra el siguiente
  /// ataque a distancia.
  bool takingCover = false;

  /// Orden Contraataque preparada: golpea primero si la cargan.
  bool counterAttack = false;

  /// Fuego de cobertura: -2" de MOV en su próxima activación.
  bool suppressed = false;

  /// Recibió disparos esta ronda (para Fuego concentrado).
  bool shotAtThisRound = false;

  /// Vigilando: dispara a la primera escuadra enemiga que se mueva a su
  /// alcance antes de su próxima activación.
  bool overwatch = false;

  /// Escuadras enemigas con las que está trabada en combate.
  final Set<String> engagedWith = {};

  /// Escuadras enemigas que destruyó en esta batalla (para la veteranía).
  int squadsDestroyed = 0;

  Iterable<Soldier> get alive => soldiers.where((s) => s.alive);
  int get aliveCount => alive.length;
  bool get destroyed => aliveCount == 0;

  /// Por debajo de la mitad de los soldados con que empezó.
  bool get belowHalf => aliveCount * 2 < startingCount;

  Iterable<Disc> get discs => alive.map((s) => s.disc);

  Soldier? soldierById(String soldierId) {
    for (final s in soldiers) {
      if (s.id == soldierId) return s;
    }
    return null;
  }

  Vec2 get centroid {
    var x = 0.0;
    var y = 0.0;
    var n = 0;
    for (final s in alive) {
      x += s.position.x;
      y += s.position.y;
      n++;
    }
    return n == 0 ? const Vec2(0, 0) : Vec2(x / n, y / n);
  }
}

/// Lo que ha hecho la escuadra activa en su activación.
final class ActivationProgress {
  bool moved = false;
  bool retreated = false;
  bool actionTaken = false;

  /// Pulgadas extra de movimiento (Avance forzado).
  double extraMove = 0;

  /// Órdenes que afectan al próximo ataque de esta activación.
  bool reroll = false;
  bool coveringFire = false;
  bool focusedFire = false;

  /// Doble paso: al terminar, el mismo bando activa otra escuadra.
  bool doubleStep = false;

  /// Posiciones y piso antes de mover, para Deshacer. Nulo si no se puede.
  Map<String, Vec2>? undoPositions;
  bool undoUpperFloor = false;
}

/// Estado completo de una batalla. Solo el [BattleEngine] lo modifica; la UI
/// lo lee.
final class BattleState {
  BattleState({
    required this.board,
    required List<Squad> squads,
    Mission? mission,
    Map<Side, List<OrderType>>? hands,
  })  : squads = List.unmodifiable(squads),
        mission = mission ?? Dominio(),
        hands = {
          for (final side in Side.values) side: [...?hands?[side]],
        } {
    final ids = <String>{};
    for (final s in squads) {
      if (!ids.add(s.id)) {
        throw ArgumentError.value(s.id, 'squads', 'Id de escuadra repetido');
      }
    }
  }

  static const int maxCommandPoints = 6;
  static const int startingCommandPoints = 2;

  final Board board;
  final List<Squad> squads;
  final Mission mission;

  /// Órdenes en la mano de cada bando. Cada una se usa una vez por batalla.
  final Map<Side, List<OrderType>> hands;

  /// Parapetos colocados por Zapadores durante la batalla.
  final List<TerrainArea> fortifications = [];

  int get maxRounds => mission.maxRounds;

  int round = 1;
  BattleStep step = BattleStep.mando;
  Side? activeSide;
  String? activeSquadId;
  ActivationProgress? progress;

  final Map<Side, int> commandPoints = {
    for (final s in Side.values) s: startingCommandPoints,
  };
  final Map<Side, int> victoryPoints = {for (final s in Side.values) s: 0};

  /// Ganador al terminar. Nulo con la batalla en curso o en tablas.
  Side? winner;

  Squad squadById(String id) {
    for (final s in squads) {
      if (s.id == id) return s;
    }
    throw ArgumentError.value(id, 'id', 'Escuadra desconocida');
  }

  Iterable<Squad> aliveSquadsOf(Side side) =>
      squads.where((s) => s.side == side && !s.destroyed);
}
