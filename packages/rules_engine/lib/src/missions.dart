import 'battle_state.dart';
import 'battlefield.dart';
import 'dice.dart';
import 'events.dart';
import 'geometry.dart';

/// Resultado de una misión que termina.
final class MissionResult {
  const MissionResult(this.winner);

  /// Nulo en tablas.
  final Side? winner;
}

/// Zona rectangular de despliegue.
final class DeploymentZone {
  const DeploymentZone(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  bool contains(Vec2 p) =>
      p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height;

  /// La misma zona ampliada [margin] pulgadas por cada lado.
  DeploymentZone inflate(double margin) => DeploymentZone(
      x - margin, y - margin, width + 2 * margin, height + 2 * margin);
}

/// Reglas propias de cada misión: rondas, zonas de despliegue y puntuación.
/// Cada batalla usa su propia instancia (algunas guardan estado).
abstract class Mission {
  String get id;
  int get maxRounds;

  /// Zonas de despliegue para un tablero de [width] × [height].
  Map<Side, DeploymentZone> deploymentZones(double width, double height) => {
        Side.jugador: DeploymentZone(0, 0, 8, height),
        Side.enemigo: DeploymentZone(width - 8, 0, 8, height),
      };

  /// Se llama una vez al empezar la batalla.
  void setup(BattleState state, Dice dice, List<GameEvent> events) {}

  /// Se llama al terminar cada activación.
  void afterActivation(
      BattleState state, Battlefield field, List<GameEvent> events) {}

  /// Paso de Puntuación. Devuelve un resultado si la misión termina.
  MissionResult? score(
      BattleState state, Battlefield field, List<GameEvent> events);

  /// Suma PV por cada objetivo puntuable que controle un bando.
  void scoreObjectives(BattleState state, Battlefield field,
      List<GameEvent> events, bool Function(Objective) scorable) {
    for (final objective in state.board.objectives) {
      if (!scorable(objective)) continue;
      final side = field.controllerOf(objective);
      if (side == null) continue;
      state.victoryPoints[side] = state.victoryPoints[side]! + objective.value;
      events.add(ObjectiveScored(objective.id, side, objective.value));
    }
  }

  /// Al final, gana quien tenga más PV.
  MissionResult byVictoryPoints(BattleState state) {
    final j = state.victoryPoints[Side.jugador]!;
    final e = state.victoryPoints[Side.enemigo]!;
    return MissionResult(j == e ? null : (j > e ? Side.jugador : Side.enemigo));
  }
}

/// Dominio: puntúan todos los objetivos desde la ronda 2. Cinco rondas.
final class Dominio extends Mission {
  @override
  String get id => 'dominio';

  @override
  int get maxRounds => 5;

  @override
  MissionResult? score(
      BattleState state, Battlefield field, List<GameEvent> events) {
    if (state.round >= 2) scoreObjectives(state, field, events, (_) => true);
    return state.round >= maxRounds ? byVictoryPoints(state) : null;
  }
}

/// Defensa del vado: [defender] gana si controla [bridgeId] al final de la
/// ronda 4; el atacante gana en cuanto lo controle en un paso de Puntuación
/// desde la ronda 2.
final class DefensaDelVado extends Mission {
  DefensaDelVado({required this.defender, this.bridgeId = 'puente'});

  final Side defender;
  final String bridgeId;

  @override
  String get id => 'defensa_vado';

  @override
  int get maxRounds => 4;

  @override
  MissionResult? score(
      BattleState state, Battlefield field, List<GameEvent> events) {
    final bridge = state.board.objectives.firstWhere((o) => o.id == bridgeId);
    final holder = field.controllerOf(bridge);
    if (holder != null && state.round >= 2) {
      state.victoryPoints[holder] = state.victoryPoints[holder]! + bridge.value;
      events.add(ObjectiveScored(bridge.id, holder, bridge.value));
    }
    final attacker = defender.opponent;
    if (state.round >= 2 && holder == attacker) return MissionResult(attacker);
    if (state.round >= maxRounds) {
      return MissionResult(holder == defender ? defender : null);
    }
    return null;
  }
}

/// Reconocimiento: los objetivos están ocultos. Al primer contacto (un
/// soldado a 3" o menos al terminar una activación) se revela si son reales
/// o señuelos. Solo puntúan los reales revelados.
final class Reconocimiento extends Mission {
  Reconocimiento({this.realCount = 3});

  final int realCount;
  final Set<String> real = {};
  final Set<String> revealed = {};

  @override
  String get id => 'reconocimiento';

  @override
  int get maxRounds => 5;

  @override
  void setup(BattleState state, Dice dice, List<GameEvent> events) {
    final pool = [for (final o in state.board.objectives) o.id];
    if (pool.length < realCount) {
      throw StateError('Reconocimiento necesita al menos $realCount objetivos.');
    }
    // Barajado de Fisher-Yates con d6: determinista con la semilla.
    while (real.length < realCount) {
      final index = _roll(dice, pool.length);
      real.add(pool.removeAt(index));
    }
  }

  /// Índice uniforme en [0, n) usando d6 (n <= 36).
  int _roll(Dice dice, int n) {
    while (true) {
      final value = (dice.d6() - 1) * 6 + (dice.d6() - 1);
      final limit = 36 - 36 % n;
      if (value < limit) return value % n;
    }
  }

  @override
  void afterActivation(
      BattleState state, Battlefield field, List<GameEvent> events) {
    for (final objective in state.board.objectives) {
      if (revealed.contains(objective.id)) continue;
      final touched = state.squads
          .where((s) => !s.destroyed)
          .any((s) => field.soldiersOn(s, objective) > 0);
      if (!touched) continue;
      revealed.add(objective.id);
      events.add(ObjectiveRevealed(objective.id, real: real.contains(objective.id)));
    }
  }

  @override
  MissionResult? score(
      BattleState state, Battlefield field, List<GameEvent> events) {
    if (state.round >= 2) {
      scoreObjectives(state, field, events,
          (o) => revealed.contains(o.id) && real.contains(o.id));
    }
    return state.round >= maxRounds ? byVictoryPoints(state) : null;
  }
}
