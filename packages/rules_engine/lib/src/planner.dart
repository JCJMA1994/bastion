import 'dart:math' as math;

import 'battle_state.dart';
import 'geometry.dart';

/// Ayudas para calcular posiciones de destino. No validan reglas: el motor
/// lo hace al aplicar el comando. Las usan la IA y la UI.
abstract final class Planner {
  /// Desplaza todos los soldados vivos de [squad] por [delta].
  static Map<String, Vec2> translate(Squad squad, Vec2 delta) =>
      {for (final s in squad.alive) s.id: s.position + delta};

  /// Punto a [maxDistance] o menos de [from] en dirección a [to].
  static Vec2 stepToward(Vec2 from, Vec2 to, double maxDistance) {
    final d = to - from;
    final len = d.length;
    if (len <= maxDistance || len == 0) return to;
    return from + d * (maxDistance / len);
  }

  /// Destinos de carga: cada soldado avanza en línea recta hacia el enemigo
  /// más cercano hasta tocarlo o agotar [distance], sin solaparse con nadie.
  /// Devuelve nulo si ningún soldado llega al contacto.
  static Map<String, Vec2>? charge(
    BattleState state,
    Squad attacker,
    Squad target, {
    required double distance,
    double contactTolerance = 0.25,
  }) {
    final enemies = target.alive.toList();
    if (enemies.isEmpty) return null;
    final blockers = <Disc>[
      for (final s in state.squads)
        if (s.id != attacker.id) ...s.discs,
    ];
    final soldiers = attacker.alive.toList()
      ..sort((a, b) => _nearest(a.position, enemies)
          .distance
          .compareTo(_nearest(b.position, enemies).distance));

    final result = <String, Vec2>{};
    var contact = false;
    for (final soldier in soldiers) {
      final nearest = _nearest(soldier.position, enemies).soldier;
      final dir = nearest.position - soldier.position;
      final len = dir.length;
      final gap = len - soldier.baseRadius - nearest.baseRadius;
      var step = math.min(distance, math.max(0.0, gap));
      Vec2? dest;
      while (step > 0.05) {
        final candidate = soldier.position + dir * (step / len);
        final disc = (center: candidate, radius: soldier.baseRadius);
        if (!blockers.any((b) => _overlaps(disc, b))) {
          dest = candidate;
          break;
        }
        step -= 0.25;
      }
      final finalPos = dest ?? soldier.position;
      final disc = (center: finalPos, radius: soldier.baseRadius);
      blockers.add(disc);
      if (dest != null) result[soldier.id] = finalPos;
      if (minEdgeDistance([disc], target.discs) <= contactTolerance) {
        contact = true;
      }
    }
    return contact ? result : null;
  }

  static ({Soldier soldier, double distance}) _nearest(
      Vec2 from, List<Soldier> candidates) {
    var best = candidates.first;
    var bestDistance = from.distanceTo(best.position);
    for (final c in candidates.skip(1)) {
      final d = from.distanceTo(c.position);
      if (d < bestDistance) {
        best = c;
        bestDistance = d;
      }
    }
    return (soldier: best, distance: bestDistance);
  }

  static bool _overlaps(Disc a, Disc b) =>
      a.center.distanceTo(b.center) < a.radius + b.radius - 1e-6;
}
