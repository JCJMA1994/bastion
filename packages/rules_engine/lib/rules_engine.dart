/// Motor de reglas de Bastión.
///
/// Dart puro y determinista: con la misma semilla y la misma lista de
/// comandos, cualquier plataforma (móvil, web o servidor) reproduce la
/// misma batalla.
library;

export 'src/ai.dart';
export 'src/battle_state.dart';
export 'src/battlefield.dart';
export 'src/campaign.dart';
export 'src/campaign_run.dart';
export 'src/combat.dart' show AttackOutcome, DiceRolls;
export 'src/odds.dart';
export 'src/commands.dart';
export 'src/deployment.dart';
export 'src/dice.dart';
export 'src/engine.dart';
export 'src/errors.dart';
export 'src/events.dart';
export 'src/geometry.dart';
export 'src/missions.dart';
export 'src/orders.dart';
export 'src/planner.dart';
export 'src/profiles.dart';
export 'src/rules.dart';
export 'src/setup.dart';
export 'src/simulation.dart';
