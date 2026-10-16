import 'dart:math' as math;

import 'battle_state.dart';
import 'dice.dart';
import 'rules.dart';

/// Datos de un ataque ya validado.
final class AttackSpec {
  const AttackSpec({
    required this.target,
    required this.attackCount,
    required this.hitTarget,
    required this.strength,
    required this.ap,
    required this.damage,
    this.hitModifier = 0,
    this.woundModifier = 0,
    this.saveBonus = 0,
    this.autoHit = false,
    this.rerollFirstMiss = false,
  });

  final Squad target;
  final int attackCount;
  final int hitTarget;
  final int strength;
  final int ap;
  final int damage;
  final int hitModifier;
  final int woundModifier;
  final int saveBonus;
  final bool autoHit;

  /// ¡Repetid!: repite el primer dado de impactar fallido.
  final bool rerollFirstMiss;
}

/// Todas las tiradas de un ataque, para enseñarlas en pantalla.
final class DiceRolls {
  const DiceRolls({
    this.hitRolls = const [],
    this.hitOn,
    this.hitModifier = 0,
    this.rerolled = false,
    this.woundRolls = const [],
    this.woundOn = 0,
    this.woundModifier = 0,
    this.saveRolls = const [],
    this.saveOn,
  });

  static const none = DiceRolls();

  /// Dados de impactar en orden; si hubo ¡Repetid!, la repetición va justo
  /// después del dado fallido.
  final List<int> hitRolls;

  /// Nulo si el arma impacta automáticamente.
  final int? hitOn;
  final int hitModifier;
  final bool rerolled;
  final List<int> woundRolls;
  final int woundOn;
  final int woundModifier;

  /// Tiradas del defensor; vacías si no había salvación posible.
  final List<int> saveRolls;
  final int? saveOn;

  Map<String, Object?> toJson() => {
        'hit': hitRolls,
        'hitOn': hitOn,
        'hitMod': hitModifier,
        'rerolled': rerolled,
        'wound': woundRolls,
        'woundOn': woundOn,
        'woundMod': woundModifier,
        'save': saveRolls,
        'saveOn': saveOn,
      };
}

final class AttackOutcome {
  const AttackOutcome({
    required this.dice,
    required this.hits,
    required this.wounds,
    required this.unsaved,
    required this.killed,
    this.rolls = DiceRolls.none,
  });

  final DiceRolls rolls;

  final int dice;
  final int hits;
  final int wounds;
  final int unsaved;
  final int killed;
}

/// Resuelve impactar, herir, salvar y daño, y aplica las bajas.
final class CombatResolver {
  CombatResolver(this._dice);

  final Dice _dice;

  AttackOutcome resolve(AttackSpec spec) {
    var hits = 0;
    final hitRolls = <int>[];
    var rerolled = false;
    if (spec.autoHit) {
      hits = spec.attackCount;
    } else {
      var rerollAvailable = spec.rerollFirstMiss;
      for (var i = 0; i < spec.attackCount; i++) {
        var roll = _dice.d6();
        hitRolls.add(roll);
        var hit = rollSucceeds(roll, spec.hitTarget, modifier: spec.hitModifier);
        if (!hit && rerollAvailable) {
          rerollAvailable = false;
          rerolled = true;
          roll = _dice.d6();
          hitRolls.add(roll);
          hit = rollSucceeds(roll, spec.hitTarget, modifier: spec.hitModifier);
        }
        if (hit) hits++;
      }
    }

    final woundOn = woundTarget(spec.strength, spec.target.profile.stats.res);
    var wounds = 0;
    final woundRolls = <int>[];
    for (var i = 0; i < hits; i++) {
      final roll = _dice.d6();
      woundRolls.add(roll);
      if (rollSucceeds(roll, woundOn, modifier: spec.woundModifier)) {
        wounds++;
      }
    }

    final saveOn = saveTarget(spec.target.profile.stats.sal, spec.ap,
        bonus: spec.saveBonus);
    var unsaved = 0;
    final saveRolls = <int>[];
    for (var i = 0; i < wounds; i++) {
      if (saveOn == null) {
        unsaved++;
        continue;
      }
      final roll = _dice.d6();
      saveRolls.add(roll);
      if (!rollSucceeds(roll, saveOn)) unsaved++;
    }

    var killed = 0;
    for (var i = 0; i < unsaved; i++) {
      final victim = _pickVictim(spec.target);
      if (victim == null) break;
      // El daño sobrante no pasa al siguiente soldado.
      victim.wounds -= math.min(victim.wounds, spec.damage);
      if (!victim.alive) killed++;
    }

    return AttackOutcome(
      dice: spec.autoHit ? 0 : spec.attackCount,
      hits: hits,
      wounds: wounds,
      unsaved: unsaved,
      killed: killed,
      rolls: DiceRolls(
        hitRolls: hitRolls,
        hitOn: spec.autoHit ? null : spec.hitTarget,
        hitModifier: spec.hitModifier,
        rerolled: rerolled,
        woundRolls: woundRolls,
        woundOn: woundOn,
        woundModifier: spec.woundModifier,
        saveRolls: saveRolls,
        saveOn: saveOn,
      ),
    );
  }

  /// El defensor reparte el daño primero en los soldados ya heridos.
  Soldier? _pickVictim(Squad squad) {
    Soldier? best;
    for (final s in squad.alive) {
      if (best == null || s.wounds < best.wounds) best = s;
    }
    return best;
  }
}
