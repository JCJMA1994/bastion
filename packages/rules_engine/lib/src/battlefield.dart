import 'battle_state.dart';
import 'geometry.dart';
import 'missions.dart';
import 'profiles.dart';

/// Consultas geométricas sobre una batalla: distancias, visión, cobertura y
/// control de objetivos. No modifica el estado, así que la UI también puede
/// usarlas para previsualizar alcances.
final class Battlefield {
  const Battlefield(this.state);

  final BattleState state;

  /// Un objetivo cuenta a 3" o menos.
  static const double objectiveRange = 3;

  /// Más de 3" de bosque en la línea bloquean la visión.
  static const double forestBlock = 3;

  Board get board => state.board;

  /// Terreno del tablero más los parapetos colocados durante la batalla.
  Iterable<TerrainArea> get terrain =>
      [...board.terrain, ...state.fortifications];

  double distance(Squad a, Squad b) => minEdgeDistance(a.discs, b.discs);

  /// Una escuadra ve a otra si al menos un par de soldados se ven.
  bool isVisible(Squad attacker, Squad target) {
    for (final a in attacker.alive) {
      for (final t in target.alive) {
        if (!isLineBlocked(a.position, t.position)) return true;
      }
    }
    return false;
  }

  bool isPointVisible(Squad attacker, Vec2 point) =>
      attacker.alive.any((a) => !isLineBlocked(a.position, point));

  bool isLineBlocked(Vec2 from, Vec2 to) => terrain.any((t) =>
      t.type == TerrainType.bosque &&
      t.polygon.lengthInside(from, to) > forestBlock);

  /// En cobertura si la mitad o más de los soldados del objetivo están dentro
  /// de un área de terreno o detrás de ella respecto al atacante.
  bool inCover(Squad attacker, Squad target) {
    final origin = attacker.centroid;
    final soldiers = target.alive.toList();
    if (soldiers.isEmpty) return false;
    var covered = 0;
    for (final s in soldiers) {
      if (_soldierCovered(origin, s.position, target.profile.role)) covered++;
    }
    return covered * 2 >= soldiers.length;
  }

  bool _soldierCovered(Vec2 origin, Vec2 position, Role role) {
    for (final area in terrain) {
      final isCrater = area.type == TerrainType.crater;
      if (isCrater && !role.isInfantry) continue;
      if (area.polygon.contains(position)) return true;
      // Los cráteres solo cubren a quien está dentro.
      if (isCrater) continue;
      // Un área que contiene al atacante no cubre al objetivo.
      if (area.polygon.contains(origin)) continue;
      if (area.polygon.lengthInside(origin, position) > 0) return true;
    }
    return false;
  }

  bool isInside(Vec2 p, TerrainType type) =>
      terrain.any((t) => t.type == type && t.polygon.contains(p));

  bool isInRuinsWithFloor(Vec2 p) => terrain.any((t) =>
      t.type == TerrainType.ruinas && t.hasFloor && t.polygon.contains(p));

  /// Soldados vivos de [squad] a 3" o menos de [objective].
  int soldiersOn(Squad squad, Objective objective) => squad.alive
      .where((s) =>
          s.position.distanceTo(objective.position) -
              s.baseRadius -
              Objective.radius <=
          objectiveRange)
      .length;

  bool isNearAnyObjective(Squad squad) =>
      board.objectives.any((o) => soldiersOn(squad, o) > 0);

  /// Bando que controla el objetivo, o nulo si nadie o empate.
  Side? controllerOf(Objective objective) {
    final count = {for (final s in Side.values) s: 0};
    for (final squad in state.squads) {
      if (squad.destroyed || squad.demoralized) continue;
      final n = soldiersOn(squad, objective) * (squad.securing ? 2 : 1);
      count[squad.side] = count[squad.side]! + n;
    }
    final j = count[Side.jugador]!;
    final e = count[Side.enemigo]!;
    if (j == e) return null;
    return j > e ? Side.jugador : Side.enemigo;
  }

  /// La escuadra contribuye a un objetivo que su bando controla.
  bool holdsObjective(Squad squad) => board.objectives.any(
      (o) => soldiersOn(squad, o) > 0 && controllerOf(o) == squad.side);

  /// Zona donde puede desplegar [squad]: la de su bando según la misión,
  /// ampliada 6" con Infiltración.
  DeploymentZone deploymentZoneFor(Squad squad) {
    final zone =
        state.mission.deploymentZones(board.width, board.height)[squad.side]!;
    return squad.profile.has(Abilities.infiltracion) ? zone.inflate(6) : zone;
  }

  /// Escuadras desplegadas fuera de su zona. Vacía si el despliegue es válido.
  List<Squad> invalidDeployments() => [
        for (final squad in state.squads)
          if (!squad.alive
              .every((s) => deploymentZoneFor(squad).contains(s.position)))
            squad,
      ];

  /// Texto de previsualización de la UI: distancia y cobertura, en datos.
  ({double distance, bool visible, bool cover}) lineOfFire(
          Squad attacker, Squad target) =>
      (
        distance: distance(attacker, target),
        visible: isVisible(attacker, target),
        cover: inCover(attacker, target),
      );

  Vec2 clampToBoard(Vec2 p) => Vec2(
        p.x.clamp(0, board.width).toDouble(),
        p.y.clamp(0, board.height).toDouble(),
      );
}
