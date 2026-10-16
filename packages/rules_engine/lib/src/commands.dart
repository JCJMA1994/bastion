import 'geometry.dart';
import 'orders.dart';

/// Intención del jugador o de la IA. El motor la valida y la aplica.
/// Una batalla se reproduce con su semilla y su lista de comandos.
sealed class Command {
  const Command();

  Map<String, Object?> toJson();

  /// Reconstruye un comando guardado con [toJson].
  static Command fromJson(Map<String, Object?> json) {
    Map<String, Vec2> destinations() => {
          for (final e
              in (json['destinations']! as Map<String, Object?>).entries)
            e.key: Vec2.fromJson(e.value! as Map<String, Object?>),
        };
    final point = json['point'] ?? json['center'];
    return switch (json['type']) {
      'activate' => ActivateSquad(json['squad']! as String),
      'move' => MoveSquad(destinations(),
          upperFloor: json['upperFloor'] as bool?),
      'shoot' => Shoot(
          weaponId: json['weapon']! as String,
          targetSquadId: json['target'] as String?,
          targetPoint:
              point == null ? null : Vec2.fromJson(point as Map<String, Object?>),
        ),
      'charge' => Charge(
          targetSquadId: json['target']! as String,
          destinations: destinations()),
      'fight' => Fight(json['target']! as String),
      'secure' => const Secure(),
      'entrench' => const Entrench(),
      'run' => Run(destinations()),
      'end_activation' => const EndActivation(),
      'play_order' => PlayOrder(OrderType.byId(json['order']! as String),
          targetSquadId: json['target'] as String?),
      'undo_move' => const UndoMove(),
      'overwatch' => const Overwatch(),
      'fortify' => Fortify(Vec2.fromJson(point! as Map<String, Object?>),
          vertical: (json['vertical'] as bool?) ?? false),
      final type => throw FormatException('Comando desconocido: $type'),
    };
  }
}

final class ActivateSquad extends Command {
  const ActivateSquad(this.squadId);
  final String squadId;

  @override
  Map<String, Object?> toJson() => {'type': 'activate', 'squad': squadId};
}

/// Mueve soldados de la escuadra activa. Los soldados que no aparecen en
/// [destinations] se quedan donde están. Una escuadra trabada solo puede
/// moverse para retirarse.
final class MoveSquad extends Command {
  const MoveSquad(this.destinations, {this.upperFloor});
  final Map<String, Vec2> destinations;

  /// Nulo: mantiene el piso actual. Cambiar de piso cuesta 2".
  final bool? upperFloor;

  @override
  Map<String, Object?> toJson() => {
        'type': 'move',
        'destinations': {
          for (final e in destinations.entries) e.key: e.value.toJson(),
        },
        'upperFloor': upperFloor,
      };
}

final class Shoot extends Command {
  const Shoot({required this.weaponId, this.targetSquadId, this.targetPoint});
  final String weaponId;
  final String? targetSquadId;

  /// Solo para armas de dispersión.
  final Vec2? targetPoint;

  @override
  Map<String, Object?> toJson() => {
        'type': 'shoot',
        'weapon': weaponId,
        'target': targetSquadId,
        'point': targetPoint?.toJson(),
      };
}

final class Charge extends Command {
  const Charge({required this.targetSquadId, required this.destinations});
  final String targetSquadId;
  final Map<String, Vec2> destinations;

  @override
  Map<String, Object?> toJson() => {
        'type': 'charge',
        'target': targetSquadId,
        'destinations': {
          for (final e in destinations.entries) e.key: e.value.toJson(),
        },
      };
}

/// Combate cuerpo a cuerpo de una escuadra ya trabada.
final class Fight extends Command {
  const Fight(this.targetSquadId);
  final String targetSquadId;

  @override
  Map<String, Object?> toJson() => {'type': 'fight', 'target': targetSquadId};
}

final class Secure extends Command {
  const Secure();
  @override
  Map<String, Object?> toJson() => {'type': 'secure'};
}

final class Entrench extends Command {
  const Entrench();
  @override
  Map<String, Object?> toJson() => {'type': 'entrench'};
}

final class Run extends Command {
  const Run(this.destinations);
  final Map<String, Vec2> destinations;

  @override
  Map<String, Object?> toJson() => {
        'type': 'run',
        'destinations': {
          for (final e in destinations.entries) e.key: e.value.toJson(),
        },
      };
}

final class EndActivation extends Command {
  const EndActivation();
  @override
  Map<String, Object?> toJson() => {'type': 'end_activation'};
}

/// Juega una orden de la mano durante la activación propia. [targetSquadId]
/// solo hace falta en las órdenes que preparan otra escuadra.
final class PlayOrder extends Command {
  const PlayOrder(this.order, {this.targetSquadId});
  final OrderType order;
  final String? targetSquadId;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'play_order', 'order': order.id, 'target': targetSquadId};
}

/// Acción de Zapadores: coloca un parapeto de 3" × 1" centrado en [center].
final class Fortify extends Command {
  const Fortify(this.center, {this.vertical = false});
  final Vec2 center;
  final bool vertical;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'fortify', 'center': center.toJson(), 'vertical': vertical};
}

/// Deshace el movimiento de la activación en curso mientras la escuadra no
/// haya actuado (mover no tira dados, así que no sirve para repetir tiradas).
final class UndoMove extends Command {
  const UndoMove();
  @override
  Map<String, Object?> toJson() => {'type': 'undo_move'};
}

/// Acción Vigilar: la escuadra no dispara ahora, pero lo hará con −1 contra la
/// primera escuadra enemiga que termine un movimiento a su alcance y a la
/// vista antes de su próxima activación.
final class Overwatch extends Command {
  const Overwatch();
  @override
  Map<String, Object?> toJson() => {'type': 'overwatch'};
}
