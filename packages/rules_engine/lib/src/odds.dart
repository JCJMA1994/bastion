import 'dart:math' as math;

import 'rules.dart';

/// Probabilidad de que un d6 supere [target] con [modifier] (con 1 y 6
/// naturales).
double successChance(int target, {int modifier = 0}) {
  var ok = 0;
  for (var r = 1; r <= 6; r++) {
    if (rollSucceeds(r, target, modifier: modifier)) ok++;
  }
  return ok / 6;
}

/// Probabilidad de que 2d6 supere [morale] (es decir, de fallar la moral).
double moraleFailChance(int morale) {
  var fail = 0;
  for (var a = 1; a <= 6; a++) {
    for (var b = 1; b <= 6; b++) {
      if (a + b > morale) fail++;
    }
  }
  return fail / 36;
}

/// Previsión de un ataque antes de hacerlo.
final class AttackOdds {
  const AttackOdds({
    required this.dice,
    required this.hitOn,
    required this.hitModifier,
    required this.woundOn,
    required this.woundModifier,
    required this.saveOn,
    required this.killDistribution,
    required this.demoralizeChance,
    this.rerollFirstMiss = false,
  });

  final int dice;

  /// Nulo si impacta automáticamente.
  final int? hitOn;
  final int hitModifier;
  final int woundOn;
  final int woundModifier;

  /// Nulo si no hay salvación posible.
  final int? saveOn;

  /// `killDistribution[k]` = probabilidad de exactamente k bajas.
  final List<double> killDistribution;

  /// Probabilidad de que el objetivo quede Desmoralizado tras el ataque.
  final double demoralizeChance;
  final bool rerollFirstMiss;

  double get expectedKills {
    var sum = 0.0;
    for (var k = 0; k < killDistribution.length; k++) {
      sum += k * killDistribution[k];
    }
    return sum;
  }

  double get anyKillChance =>
      killDistribution.isEmpty ? 0 : 1 - killDistribution.first;

  /// Probabilidad de destruir la escuadra entera.
  double get destroyChance =>
      killDistribution.isEmpty ? 0 : killDistribution.last;

  /// Calcula la previsión. [targetWounds] son las heridas que le quedan a
  /// cada soldado vivo del objetivo; [startingCount], los soldados con que
  /// empezó la batalla (para la moral).
  factory AttackOdds.compute({
    required int dice,
    required int? hitOn,
    int hitModifier = 0,
    required int woundOn,
    int woundModifier = 0,
    required int? saveOn,
    required int damage,
    required List<int> targetWounds,
    required int startingCount,
    required int morale,
    bool alreadyDemoralized = false,
    bool rerollFirstMiss = false,
  }) {
    var pHit = hitOn == null ? 1.0 : successChance(hitOn, modifier: hitModifier);
    // ¡Repetid! repite un único fallo: se aproxima repartiendo su efecto
    // entre todos los dados (exacto en media).
    if (rerollFirstMiss && hitOn != null && dice > 0) {
      final pAnyMiss = 1 - math.pow(pHit, dice).toDouble();
      pHit += pAnyMiss * pHit / dice;
    }
    final pWound = successChance(woundOn, modifier: woundModifier);
    final pFail = saveOn == null ? 1.0 : 1 - successChance(saveOn);
    final p = (pHit * pWound * pFail).clamp(0.0, 1.0).toDouble();

    final alive = targetWounds.length;
    final distribution = List<double>.filled(alive + 1, 0);
    for (var n = 0; n <= dice; n++) {
      final kills = _killsFor(n, damage, targetWounds);
      distribution[kills] += _binomial(dice, n, p);
    }

    var demoralize = 0.0;
    if (!alreadyDemoralized) {
      final fail = moraleFailChance(morale);
      for (var k = 1; k < alive; k++) {
        final remaining = alive - k;
        if (remaining * 2 < startingCount) demoralize += distribution[k] * fail;
      }
    }

    return AttackOdds(
      dice: dice,
      hitOn: hitOn,
      hitModifier: hitModifier,
      woundOn: woundOn,
      woundModifier: woundModifier,
      saveOn: saveOn,
      killDistribution: distribution,
      demoralizeChance: demoralize,
      rerollFirstMiss: rerollFirstMiss,
    );
  }

  /// Bajas que causan [unsaved] heridas, repartidas como el motor: siempre
  /// al soldado con menos heridas, sin daño sobrante.
  static int _killsFor(int unsaved, int damage, List<int> wounds) {
    final left = [...wounds];
    var kills = 0;
    for (var i = 0; i < unsaved; i++) {
      var best = -1;
      for (var j = 0; j < left.length; j++) {
        if (left[j] > 0 && (best < 0 || left[j] < left[best])) best = j;
      }
      if (best < 0) break;
      left[best] -= math.min(left[best], damage);
      if (left[best] == 0) kills++;
    }
    return kills;
  }

  static double _binomial(int n, int k, double p) {
    var c = 1.0;
    for (var i = 0; i < k; i++) {
      c = c * (n - i) / (i + 1);
    }
    return c * math.pow(p, k) * math.pow(1 - p, n - k);
  }
}
