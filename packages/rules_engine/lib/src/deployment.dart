import 'battle_state.dart';
import 'battlefield.dart';
import 'errors.dart';
import 'geometry.dart';

/// Despliegue antes de la batalla: coloca escuadras en formación dentro de
/// su zona. Se usa antes de `BattleEngine.start()`.
final class Deployment {
  Deployment(this.state) : field = Battlefield(state);

  final BattleState state;
  final Battlefield field;

  /// Separación entre centros de soldados en la formación (peanas de 1").
  static const double spacing = 1.5;

  /// Posiciones de una formación de hasta 3 en fondo centrada en [center].
  static List<Vec2> formation(int soldiers, Vec2 center) {
    final columns = soldiers < 3 ? soldiers : 3;
    final rows = (soldiers + 2) ~/ 3;
    final width = (columns - 1) * spacing;
    final height = (rows - 1) * spacing;
    return [
      for (var i = 0; i < soldiers; i++)
        Vec2(center.x - width / 2 + (i % 3) * spacing,
            center.y - height / 2 + (i ~/ 3) * spacing),
    ];
  }

  /// Coloca [squad] en formación en [center]. Lanza [RuleViolation] si queda
  /// fuera de su zona, del tablero o encima de otra escuadra.
  void place(Squad squad, Vec2 center) {
    final positions = formation(squad.aliveCount, center);
    final zone = field.deploymentZoneFor(squad);
    for (final p in positions) {
      if (!zone.contains(p)) {
        throw const RuleViolation(ViolationCode.fueraDeZona);
      }
      if (p.x < 0.5 || p.y < 0.5 ||
          p.x > state.board.width - 0.5 || p.y > state.board.height - 0.5) {
        throw const RuleViolation(ViolationCode.fueraDelTablero);
      }
      for (final other in state.squads) {
        if (other.id == squad.id) continue;
        for (final s in other.alive) {
          if (s.position.distanceTo(p) < s.baseRadius + 0.5 - 1e-6) {
            throw const RuleViolation(ViolationCode.solapamiento);
          }
        }
      }
    }
    final alive = squad.alive.toList();
    for (var i = 0; i < alive.length; i++) {
      alive[i].position = positions[i];
    }
  }

  /// Reparte las escuadras de [side] a lo largo de su zona, de arriba abajo.
  /// Primero las aparta para que no estorben a la recolocación.
  void autoDeploy(Side side) {
    final squads = state.aliveSquadsOf(side).toList();
    if (squads.isEmpty) return;
    for (final squad in squads) {
      for (final s in squad.alive) {
        s.position = const Vec2(-100, -100);
      }
    }
    final zones = state.mission
        .deploymentZones(state.board.width, state.board.height);
    final zone = zones[side]!;
    final x = zone.x + zone.width / 2;
    final step = zone.height / squads.length;
    for (var i = 0; i < squads.length; i++) {
      final y = zone.y + step * (i + 0.5);
      place(squads[i], Vec2(x, y));
    }
  }
}
