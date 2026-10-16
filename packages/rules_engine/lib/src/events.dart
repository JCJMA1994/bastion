import 'battle_state.dart';
import 'combat.dart' show DiceRolls;
import 'geometry.dart';
import 'orders.dart';

/// Lo que ocurrió al aplicar un comando. La UI anima los eventos en orden y
/// los textos salen de la guía de copy, no del motor.
sealed class GameEvent {
  const GameEvent();
  Map<String, Object?> toJson();
}

final class RoundStarted extends GameEvent {
  const RoundStarted(this.round);
  final int round;
  @override
  Map<String, Object?> toJson() => {'type': 'round_started', 'round': round};
}

final class CommandPointsGained extends GameEvent {
  const CommandPointsGained(this.side, this.gained, this.total);
  final Side side;
  final int gained;
  final int total;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'pm_gained', 'side': side.name, 'gained': gained, 'total': total};
}

final class SquadRallied extends GameEvent {
  const SquadRallied(this.squadId, this.roll, {required this.success});
  final String squadId;
  final int roll;
  final bool success;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'rally', 'squad': squadId, 'roll': roll, 'success': success};
}

final class InitiativeDecided extends GameEvent {
  const InitiativeDecided(this.side);
  final Side side;
  @override
  Map<String, Object?> toJson() => {'type': 'initiative', 'side': side.name};
}

final class TurnPassed extends GameEvent {
  const TurnPassed(this.side);
  final Side side;
  @override
  Map<String, Object?> toJson() => {'type': 'turn', 'side': side.name};
}

final class ActivationStarted extends GameEvent {
  const ActivationStarted(this.squadId);
  final String squadId;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'activation_started', 'squad': squadId};
}

final class SquadMoved extends GameEvent {
  const SquadMoved(this.squadId, {required this.kind});
  final String squadId;

  /// 'move', 'run', 'retreat' o 'charge'.
  final String kind;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'moved', 'squad': squadId, 'kind': kind};
}

final class AttackResolved extends GameEvent {
  const AttackResolved({
    required this.attackerId,
    required this.targetId,
    required this.weaponId,
    required this.dice,
    required this.hits,
    required this.wounds,
    required this.unsaved,
    required this.killed,
    this.rolls = DiceRolls.none,
    this.reaction = false,
  });

  /// Las tiradas, para mostrarlas.
  final DiceRolls rolls;

  /// Disparo de reacción (Vigilar).
  final bool reaction;
  final String attackerId;
  final String targetId;
  final String weaponId;
  final int dice;
  final int hits;
  final int wounds;
  final int unsaved;
  final int killed;
  @override
  Map<String, Object?> toJson() => {
        'type': 'attack',
        'attacker': attackerId,
        'target': targetId,
        'weapon': weaponId,
        'dice': dice,
        'hits': hits,
        'wounds': wounds,
        'unsaved': unsaved,
        'killed': killed,
        'rolls': rolls.toJson(),
        if (reaction) 'reaction': true,
      };
}

final class ScatterResolved extends GameEvent {
  const ScatterResolved({
    required this.squadId,
    required this.aimed,
    required this.landed,
    required this.accuracyRoll,
  });
  final String squadId;
  final Vec2 aimed;
  final Vec2 landed;
  final int accuracyRoll;
  @override
  Map<String, Object?> toJson() => {
        'type': 'scatter',
        'squad': squadId,
        'aimed': aimed.toJson(),
        'landed': landed.toJson(),
        'roll': accuracyRoll,
      };
}

final class ChargeMade extends GameEvent {
  const ChargeMade(this.attackerId, this.targetId);
  final String attackerId;
  final String targetId;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'charge', 'attacker': attackerId, 'target': targetId};
}

final class SquadSecuring extends GameEvent {
  const SquadSecuring(this.squadId);
  final String squadId;
  @override
  Map<String, Object?> toJson() => {'type': 'securing', 'squad': squadId};
}

final class SquadEntrenched extends GameEvent {
  const SquadEntrenched(this.squadId);
  final String squadId;
  @override
  Map<String, Object?> toJson() => {'type': 'entrenched', 'squad': squadId};
}

final class MoraleChecked extends GameEvent {
  const MoraleChecked(this.squadId, this.roll, this.morale,
      {required this.passed});
  final String squadId;
  final int roll;
  final int morale;
  final bool passed;
  @override
  Map<String, Object?> toJson() => {
        'type': 'morale',
        'squad': squadId,
        'roll': roll,
        'morale': morale,
        'passed': passed,
      };
}

final class SquadDestroyed extends GameEvent {
  const SquadDestroyed(this.squadId, this.byId);
  final String squadId;
  final String byId;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'destroyed', 'squad': squadId, 'by': byId};
}

final class ActivationEnded extends GameEvent {
  const ActivationEnded(this.squadId);
  final String squadId;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'activation_ended', 'squad': squadId};
}

final class ObjectiveScored extends GameEvent {
  const ObjectiveScored(this.objectiveId, this.side, this.points);
  final String objectiveId;
  final Side side;
  final int points;
  @override
  Map<String, Object?> toJson() => {
        'type': 'objective_scored',
        'objective': objectiveId,
        'side': side.name,
        'points': points,
      };
}

final class BattleEnded extends GameEvent {
  const BattleEnded(this.winner);

  /// Nulo en tablas.
  final Side? winner;
  @override
  Map<String, Object?> toJson() => {'type': 'battle_ended', 'winner': winner?.name};
}

final class OrderPlayed extends GameEvent {
  const OrderPlayed(this.side, this.order, this.squadId, this.remainingPoints);
  final Side side;
  final OrderType order;
  final String squadId;
  final int remainingPoints;
  @override
  Map<String, Object?> toJson() => {
        'type': 'order',
        'side': side.name,
        'order': order.id,
        'squad': squadId,
        'pm': remainingPoints,
      };
}

final class Fortified extends GameEvent {
  const Fortified(this.squadId, this.terrainId);
  final String squadId;
  final String terrainId;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'fortified', 'squad': squadId, 'terrain': terrainId};
}

final class ObjectiveRevealed extends GameEvent {
  const ObjectiveRevealed(this.objectiveId, {required this.real});
  final String objectiveId;
  final bool real;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'objective_revealed', 'objective': objectiveId, 'real': real};
}

final class SquadOverwatching extends GameEvent {
  const SquadOverwatching(this.squadId);
  final String squadId;
  @override
  Map<String, Object?> toJson() => {'type': 'overwatch', 'squad': squadId};
}

final class OverwatchTriggered extends GameEvent {
  const OverwatchTriggered(this.watcherId, this.targetId);
  final String watcherId;
  final String targetId;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'overwatch_fire', 'watcher': watcherId, 'target': targetId};
}
