import 'battle_state.dart';
import 'commands.dart';
import 'engine.dart';
import 'errors.dart';
import 'events.dart';
import 'geometry.dart';
import 'orders.dart';
import 'planner.dart';
import 'profiles.dart';

/// IA del MVP. Juega una activación completa aplicando comandos al motor:
///
/// 1. Prepara defensas con órdenes: Arenga a escuadras Desmoralizadas,
///    Contraataque si hay amenazas cuerpo a cuerpo cerca y Cuerpo a tierra si
///    está bajo el fuego enemigo.
/// 2. Si puede cargar con una escuadra de asalto o caballería, carga.
/// 3. Si no, se acerca al objetivo más valioso que no controla (con Avance
///    forzado si no llega), salvo la artillería, que no mueve para disparar.
/// 4. Dispara al enemigo visible más cercano, reforzando el disparo con
///    Fuego concentrado, Fuego de cobertura o ¡Repetid! cuando compensa; si
///    no puede disparar, asegura un objetivo cercano o vigila.
///
/// Nunca bloquea la partida: si un comando es inválido, prueba el siguiente
/// paso y, como último recurso, termina la activación.
final class SimpleAi {
  const SimpleAi({this.useOrders = true});

  /// Con `false`, la IA no juega órdenes (útil para medir su efecto).
  final bool useOrders;

  /// Distancia a la que una escuadra enemiga cuerpo a cuerpo es una amenaza.
  static const double _meleeThreat = 12;

  List<GameEvent> playActivation(BattleEngine engine, Side side) {
    final events = <GameEvent>[];
    final state = engine.state;
    final squad =
        state.aliveSquadsOf(side).firstWhere((s) => !s.activatedThisRound);

    bool tryApply(Command command) {
      try {
        events.addAll(engine.apply(command));
        return true;
      } on RuleViolation {
        return false;
      }
    }

    bool activationOpen() => state.activeSquadId == squad.id;

    tryApply(ActivateSquad(squad.id));
    if (!activationOpen()) return events;

    final orders = _Orders(engine, side, tryApply, enabled: useOrders);
    _prepareDefences(engine, squad, orders);

    if (squad.engagedWith.isNotEmpty) {
      tryApply(Fight(squad.engagedWith.first));
    } else if (!_tryCharge(engine, squad, tryApply)) {
      if (squad.profile.role != Role.artilleria) {
        _advance(engine, squad, tryApply, orders);
      }
      if (activationOpen()) _shootOrSecure(engine, squad, tryApply, orders);
    }

    if (activationOpen()) tryApply(const EndActivation());
    return events;
  }

  void _prepareDefences(BattleEngine engine, Squad squad, _Orders orders) {
    final state = engine.state;
    final field = engine.field;
    final own = state.aliveSquadsOf(squad.side).toList();
    final enemies = state.aliveSquadsOf(squad.side.opponent).toList();

    // Arenga: la escuadra Desmoralizada más numerosa.
    final demoralized = own.where((s) => s.demoralized).toList()
      ..sort((a, b) => b.aliveCount.compareTo(a.aliveCount));
    if (demoralized.isNotEmpty) {
      orders.play(OrderType.arenga, target: demoralized.first);
    }

    // Contraataque: escuadra propia amenazada por un enemigo cuerpo a cuerpo
    // (la activa queda protegida hasta su activación de la ronda siguiente).
    bool isMelee(Squad s) =>
        s.profile.has(Abilities.asalto) ||
        s.profile.has(Abilities.cargaDevastadora);
    final threatened = own.where((s) =>
        !s.counterAttack &&
        enemies.any((e) => isMelee(e) && field.distance(e, s) <= _meleeThreat));
    final counterTarget = threatened.contains(squad)
        ? squad
        : threatened.where((s) => s.activatedThisRound).firstOrNull;
    if (counterTarget != null) {
      orders.play(OrderType.contraataque, target: counterTarget);
    }

    // Cuerpo a tierra: la escuadra activa si algún enemigo la ve y la alcanza.
    final underFire = enemies.any((e) => e.profile.weapons.any((w) =>
        !w.isMelee &&
        field.isVisible(e, squad) &&
        field.distance(e, squad) <= w.range));
    if (underFire && !squad.takingCover && squad.aliveCount >= 3) {
      orders.play(OrderType.cuerpoATierra, target: squad, reserve: 1);
    }
  }

  bool _tryCharge(
      BattleEngine engine, Squad squad, bool Function(Command) tryApply) {
    final melee = squad.profile.has(Abilities.asalto) ||
        squad.profile.has(Abilities.cargaDevastadora);
    if (!melee || squad.demoralized) return false;
    final distance = squad.profile.has(Abilities.asalto)
        ? BattleEngine.assaultChargeDistance
        : BattleEngine.chargeDistance;
    for (final target in _enemiesByDistance(engine, squad)) {
      if (engine.field.distance(squad, target) > BattleEngine.chargeRange) break;
      final plan = Planner.charge(engine.state, squad, target, distance: distance);
      if (plan != null &&
          tryApply(Charge(targetSquadId: target.id, destinations: plan))) {
        return true;
      }
    }
    return false;
  }

  void _advance(BattleEngine engine, Squad squad,
      bool Function(Command) tryApply, _Orders orders) {
    final state = engine.state;
    Objective? goal;
    var best = double.infinity;
    for (final o in state.board.objectives) {
      if (engine.field.controllerOf(o) == squad.side) continue;
      final d = squad.centroid.distanceTo(o.position) / o.value;
      if (d < best) {
        best = d;
        goal = o;
      }
    }
    if (goal == null) return;
    final centroid = squad.centroid;
    var reach = squad.profile.stats.mov.toDouble();
    final far = centroid.distanceTo(goal.position) > reach + 1;
    if (far && orders.play(OrderType.avanceForzado, reserve: 1)) {
      reach += BattleEngine.forcedMarchBonus;
    }
    final full = Planner.stepToward(centroid, goal.position, reach) - centroid;
    for (final fraction in const [1.0, 0.75, 0.5, 0.25]) {
      final delta = full * fraction;
      if (delta.length < 0.25) return;
      if (tryApply(MoveSquad(Planner.translate(squad, delta)))) return;
    }
  }

  void _shootOrSecure(BattleEngine engine, Squad squad,
      bool Function(Command) tryApply, _Orders orders) {
    final field = engine.field;
    final moved = engine.state.progress?.moved ?? false;
    for (final weapon in squad.profile.weapons.where((w) => !w.isMelee)) {
      if (weapon.mode == HitMode.dispersion && moved) continue;
      for (final target in _enemiesByDistance(engine, squad)) {
        if (!field.isVisible(squad, target)) continue;
        if (field.distance(squad, target) > weapon.range) break;
        final command = weapon.mode == HitMode.dispersion
            ? Shoot(weaponId: weapon.id, targetPoint: _nearestSoldier(squad, target))
            : Shoot(weaponId: weapon.id, targetSquadId: target.id);
        _boostShot(squad, target, weapon, orders);
        if (tryApply(command)) return;
      }
    }
    if (field.isNearAnyObjective(squad)) {
      tryApply(const Secure());
      return;
    }
    // Sin blanco: vigila si algún enemigo puede ponerse a tiro en su turno.
    final watchWeapon = squad.profile.weapons
        .where((w) => !w.isMelee && w.mode != HitMode.dispersion)
        .firstOrNull;
    if (watchWeapon != null &&
        _enemiesByDistance(engine, squad).any((e) =>
            field.distance(squad, e) <=
            watchWeapon.range + e.profile.stats.mov + 3)) {
      tryApply(const Overwatch());
    }
  }

  /// Órdenes de ataque: como mucho una por disparo, la más rentable.
  void _boostShot(Squad squad, Squad target, Weapon weapon, _Orders orders) {
    final dice = squad.aliveCount * weapon.attacks;
    final melee = target.profile.has(Abilities.asalto) ||
        target.profile.has(Abilities.cargaDevastadora);
    if (target.shotAtThisRound &&
        dice >= 3 &&
        orders.play(OrderType.fuegoConcentrado)) {
      return;
    }
    if (melee && orders.play(OrderType.fuegoCobertura, reserve: 1)) return;
    if (dice >= 4 && weapon.mode == HitMode.normal) {
      orders.play(OrderType.repetid, reserve: 1);
    }
  }

  List<Squad> _enemiesByDistance(BattleEngine engine, Squad squad) =>
      engine.state.aliveSquadsOf(squad.side.opponent).toList()
        ..sort((a, b) => engine.field
            .distance(squad, a)
            .compareTo(engine.field.distance(squad, b)));

  /// Para la dispersión, apunta al soldado enemigo más cercano.
  Vec2 _nearestSoldier(Squad from, Squad target) {
    final c = from.centroid;
    return target.alive
        .reduce((a, b) =>
            c.distanceTo(a.position) <= c.distanceTo(b.position) ? a : b)
        .position;
  }
}

/// Juega órdenes de la mano si hay PM, dejando [reserve] PM de margen.
final class _Orders {
  _Orders(this.engine, this.side, this.tryApply, {required this.enabled});

  final BattleEngine engine;
  final Side side;
  final bool Function(Command) tryApply;
  final bool enabled;

  bool play(OrderType order, {Squad? target, int reserve = 0}) {
    if (!enabled) return false;
    final state = engine.state;
    if (!state.hands[side]!.contains(order)) return false;
    if (state.commandPoints[side]! < order.cost + reserve) return false;
    return tryApply(PlayOrder(order, targetSquadId: target?.id));
  }
}
