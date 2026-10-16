import 'dart:math' as math;

import 'battle_state.dart';
import 'battlefield.dart';
import 'combat.dart';
import 'commands.dart';
import 'dice.dart';
import 'errors.dart';
import 'events.dart';
import 'geometry.dart';
import 'odds.dart';
import 'orders.dart';
import 'profiles.dart';
import 'rules.dart';

/// Aplica comandos sobre un [BattleState] siguiendo el reglamento del MVP.
///
/// Cada comando se valida por completo antes de tocar el estado: si lanza
/// [RuleViolation], nada cambia.
final class BattleEngine {
  BattleEngine({required this.state, required Dice dice})
      : _dice = dice,
        _combat = CombatResolver(dice),
        field = Battlefield(state);

  final BattleState state;
  final Battlefield field;
  final Dice _dice;
  final CombatResolver _combat;

  /// Comandos aplicados con éxito, en orden. Con la semilla, reproducen la
  /// batalla.
  final List<Command> history = [];

  /// Escuadras que perdieron soldados durante la activación en curso.
  final Set<String> _lostThisActivation = {};
  bool _started = false;

  static const double coherencyRange = 2;
  static const double chargeRange = 9;
  static const double chargeDistance = 3;
  static const double assaultChargeDistance = 5;
  static const double retreatClearance = 1;
  static const double floorChangeCost = 2;
  static const double forestPenalty = 2;
  static const double scatterRadius = 2;
  static const double contactTolerance = 0.25;
  static const double captainAuraRange = 6;
  static const double suppressionPenalty = 2;

  /// Penalización del disparo de reacción (Vigilar).
  static const int overwatchPenalty = -1;
  static const double forcedMarchBonus = 3;
  static const double fortifyReach = 2;
  static const double parapetLength = 3;
  static const double parapetDepth = 1;
  static const int captainAuraMorale = 8;
  static const double _epsilon = 1e-6;

  // ---------------------------------------------------------------- API

  /// Inicia la batalla: ejecuta el Mando de la ronda 1.
  List<GameEvent> start() {
    if (_started) throw StateError('La batalla ya empezó.');
    _started = true;
    final events = <GameEvent>[];
    state.mission.setup(state, _dice, events);
    _beginRound(events);
    return events;
  }

  List<GameEvent> apply(Command command) {
    if (!_started) {
      throw const RuleViolation(ViolationCode.batallaNoIniciada);
    }
    if (state.step == BattleStep.terminada) {
      throw const RuleViolation(ViolationCode.batallaTerminada);
    }
    final events = <GameEvent>[];
    switch (command) {
      case final ActivateSquad c:
        _activate(c, events);
      case final MoveSquad c:
        _move(c, events);
      case final Shoot c:
        _shoot(c, events);
      case final Charge c:
        _charge(c, events);
      case final Fight c:
        _fight(c, events);
      case Secure():
        _secure(events);
      case Entrench():
        _entrench(events);
      case final Run c:
        _run(c, events);
      case final PlayOrder c:
        _playOrder(c, events);
      case final Fortify c:
        _fortify(c, events);
      case UndoMove():
        _undoMove(events);
      case Overwatch():
        _overwatch(events);
      case EndActivation():
        _activeSquad();
        _endActivation(events);
    }
    history.add(command);
    return events;
  }

  // ---------------------------------------------------- previsualización

  /// Probabilidades de disparar con [weaponId] de [attackerId] a [targetId]
  /// con las reglas y órdenes activas ahora mismo. Nulo si no hay disparo
  /// posible que prever (arma CaC o de dispersión, objetivo destruido).
  AttackOdds? previewShot(String attackerId, String targetId, String weaponId) {
    final attacker = state.squadById(attackerId);
    final target = state.squadById(targetId);
    if (attacker.destroyed || target.destroyed) return null;
    final weapon = attacker.profile.weapons.where((w) => w.id == weaponId).firstOrNull;
    if (weapon == null || weapon.isMelee || weapon.mode == HitMode.dispersion) {
      return null;
    }
    final progress = state.activeSquadId == attackerId
        ? state.progress ?? ActivationProgress()
        : ActivationProgress();
    final auto = weapon.mode == HitMode.automatico;
    return _odds(
      attacker: attacker,
      target: target,
      dice: attacker.aliveCount * weapon.attacks,
      hitOn: auto ? null : attacker.profile.stats.pun,
      hitModifier: auto
          ? 0
          : _shootingModifier(attacker, target, progress,
              ignoreCover: attacker.profile.has(Abilities.ojoDeHalcon)),
      strength: weapon.strength,
      ap: weapon.ap,
      damage: weapon.damage,
      woundModifier: progress.focusedFire && target.shotAtThisRound ? 1 : 0,
      saveBonus: _rangedSaveBonus(target),
      reroll: progress.reroll,
    );
  }

  /// Probabilidades del golpe de [attackerId] a [targetId] en cuerpo a
  /// cuerpo (solo el primer golpe, sin la respuesta).
  AttackOdds? previewMelee(String attackerId, String targetId,
      {bool charging = false}) {
    final attacker = state.squadById(attackerId);
    final target = state.squadById(targetId);
    if (attacker.destroyed || target.destroyed) return null;
    final weapon = attacker.profile.meleeWeapon;
    final bonus =
        charging && attacker.profile.has(Abilities.cargaDevastadora) ? 1 : 0;
    return _odds(
      attacker: attacker,
      target: target,
      dice: attacker.aliveCount * weapon.attacks,
      hitOn: weapon.meleeHit,
      hitModifier: clampModifier(attacker.demoralized ? -1 : 0),
      strength: weapon.strength + bonus,
      ap: weapon.ap,
      damage: weapon.damage,
      saveBonus: target.entrenched ? 1 : 0,
    );
  }

  AttackOdds _odds({
    required Squad attacker,
    required Squad target,
    required int dice,
    required int? hitOn,
    required int hitModifier,
    required int strength,
    required int ap,
    required int damage,
    int woundModifier = 0,
    int saveBonus = 0,
    bool reroll = false,
  }) =>
      AttackOdds.compute(
        dice: dice,
        hitOn: hitOn,
        hitModifier: hitModifier,
        woundOn: woundTarget(strength, target.profile.stats.res),
        woundModifier: woundModifier,
        saveOn: saveTarget(target.profile.stats.sal, ap, bonus: saveBonus),
        damage: damage,
        targetWounds: [for (final s in target.alive) s.wounds],
        startingCount: target.startingCount,
        morale: _effectiveMorale(target),
        alreadyDemoralized: target.demoralized,
        rerollFirstMiss: reroll,
      );

  // ---------------------------------------------------------- comandos

  void _activate(ActivateSquad c, List<GameEvent> events) {
    if (state.step != BattleStep.activaciones) {
      throw const RuleViolation(ViolationCode.pasoIncorrecto);
    }
    if (state.activeSquadId != null) {
      throw const RuleViolation(ViolationCode.activacionEnCurso);
    }
    final squad = _squad(c.squadId);
    if (squad.side != state.activeSide) {
      throw const RuleViolation(ViolationCode.turnoDelOtroBando);
    }
    if (squad.destroyed) {
      throw const RuleViolation(ViolationCode.escuadraDestruida);
    }
    if (squad.activatedThisRound) {
      throw const RuleViolation(ViolationCode.escuadraYaActivada);
    }
    squad
      ..entrenched = false
      ..takingCover = false
      ..counterAttack = false
      ..overwatch = false;
    state.activeSquadId = squad.id;
    state.progress = ActivationProgress();
    _lostThisActivation.clear();
    events.add(ActivationStarted(squad.id));
  }

  void _move(MoveSquad c, List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    if (progress.moved) throw const RuleViolation(ViolationCode.yaMovio);
    _requireNoAction(progress);

    final engaged = _engagedEnemies(squad);
    final targetFloor = c.upperFloor ?? squad.upperFloor;
    final projected = _projected(squad, c.destinations);

    var allowance = _baseMovement(squad) + progress.extraMove;
    if (targetFloor != squad.upperFloor) {
      allowance -= floorChangeCost;
      if (targetFloor) {
        final onFloor = projected.values
            .where((d) => field.isInRuinsWithFloor(d.center))
            .length;
        if (onFloor * 2 < projected.length) {
          throw const RuleViolation(ViolationCode.sinPisoElevado);
        }
      }
    }
    if (!squad.profile.role.isInfantry &&
        projected.values
            .any((d) => field.isInside(d.center, TerrainType.bosque))) {
      allowance -= forestPenalty;
    }

    _validateDestinations(squad, c.destinations, math.max(0.0, allowance));

    if (engaged.isNotEmpty) {
      for (final enemy in engaged) {
        if (minEdgeDistance(projected.values, enemy.discs) <=
            retreatClearance) {
          throw const RuleViolation(ViolationCode.retiradaInsuficiente);
        }
      }
    }

    if (engaged.isEmpty) {
      progress
        ..undoPositions = {for (final s in squad.alive) s.id: s.position}
        ..undoUpperFloor = squad.upperFloor;
    }
    _applyPositions(squad, c.destinations);
    squad.upperFloor = targetFloor;
    progress.moved = true;
    if (engaged.isNotEmpty) {
      for (final enemy in engaged) {
        squad.engagedWith.remove(enemy.id);
        enemy.engagedWith.remove(squad.id);
      }
      progress.retreated = true;
    }
    events.add(SquadMoved(squad.id, kind: engaged.isEmpty ? 'move' : 'retreat'));
    if (_triggerOverwatch(squad, events)) {
      // Ya hubo dados: el movimiento no se puede deshacer.
      progress.undoPositions = null;
      if (squad.destroyed) {
        progress.actionTaken = true;
        _endActivation(events);
      }
    }
  }

  void _undoMove(List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    final before = progress.undoPositions;
    if (!progress.moved || progress.actionTaken || before == null) {
      throw const RuleViolation(ViolationCode.nadaQueDeshacer);
    }
    _applyPositions(squad, before);
    squad.upperFloor = progress.undoUpperFloor;
    progress
      ..moved = false
      ..undoPositions = null;
    events.add(SquadMoved(squad.id, kind: 'undo'));
  }

  void _overwatch(List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    _requireNotRetreated(progress);
    _requireNotEngaged(squad);
    if (_overwatchWeapon(squad) == null) {
      throw const RuleViolation(ViolationCode.sinArmaParaVigilar);
    }
    squad.overwatch = true;
    progress.actionTaken = true;
    events.add(SquadOverwatching(squad.id));
    _endActivation(events);
  }

  /// Arma con la que se vigila: la primera a distancia que no sea de
  /// dispersión.
  Weapon? _overwatchWeapon(Squad squad) {
    for (final w in squad.profile.weapons) {
      if (!w.isMelee && w.mode != HitMode.dispersion) return w;
    }
    return null;
  }

  /// Las escuadras enemigas que vigilan disparan a [mover] si quedó a su
  /// alcance y a la vista. Devuelve si alguna disparó.
  bool _triggerOverwatch(Squad mover, List<GameEvent> events) {
    var fired = false;
    for (final watcher in state.squads) {
      if (mover.destroyed) break;
      if (watcher.side == mover.side ||
          watcher.destroyed ||
          !watcher.overwatch ||
          watcher.engagedWith.isNotEmpty) {
        continue;
      }
      final weapon = _overwatchWeapon(watcher);
      if (weapon == null ||
          !field.isVisible(watcher, mover) ||
          field.distance(watcher, mover) > weapon.range + _epsilon) {
        continue;
      }
      watcher.overwatch = false;
      fired = true;
      events.add(OverwatchTriggered(watcher.id, mover.id));
      final auto = weapon.mode == HitMode.automatico;
      final outcome = _combat.resolve(AttackSpec(
        target: mover,
        attackCount: watcher.aliveCount * weapon.attacks,
        hitTarget: watcher.profile.stats.pun,
        hitModifier: _reactionModifier(watcher, mover,
            ignoreCover: auto || watcher.profile.has(Abilities.ojoDeHalcon)),
        strength: weapon.strength,
        ap: weapon.ap,
        damage: weapon.damage,
        saveBonus: _rangedSaveBonus(mover),
        autoHit: auto,
      ));
      _afterRangedAttack(mover, outcome, ActivationProgress());
      _report(watcher, mover, weapon, outcome, events, reaction: true);
    }
    return fired;
  }

  int _reactionModifier(Squad watcher, Squad target, {required bool ignoreCover}) {
    var mod = overwatchPenalty;
    if (watcher.demoralized) mod -= 1;
    if (!ignoreCover && field.inCover(watcher, target)) mod -= 1;
    if (watcher.upperFloor && !target.upperFloor) mod += 1;
    return clampModifier(mod);
  }

  void _shoot(Shoot c, List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    _requireNotRetreated(progress);
    _requireNotEngaged(squad);
    final weapon = squad.profile.weaponById(c.weaponId);
    if (weapon.isMelee) throw const RuleViolation(ViolationCode.armaNoValida);

    if (weapon.mode == HitMode.dispersion) {
      _scatterShot(squad, weapon, c.targetPoint, progress, events);
    } else {
      final targetId = c.targetSquadId ??
          (throw const RuleViolation(ViolationCode.objetivoRequerido));
      final target = _enemySquad(squad, targetId);
      if (!field.isVisible(squad, target)) {
        throw const RuleViolation(ViolationCode.sinVision);
      }
      if (field.distance(squad, target) > weapon.range + _epsilon) {
        throw const RuleViolation(ViolationCode.fueraDeAlcance);
      }
      final auto = weapon.mode == HitMode.automatico;
      final outcome = _combat.resolve(AttackSpec(
        target: target,
        attackCount: squad.aliveCount * weapon.attacks,
        hitTarget: squad.profile.stats.pun,
        hitModifier: _shootingModifier(squad, target, progress,
            ignoreCover: auto || squad.profile.has(Abilities.ojoDeHalcon)),
        strength: weapon.strength,
        ap: weapon.ap,
        damage: weapon.damage,
        woundModifier: progress.focusedFire && target.shotAtThisRound ? 1 : 0,
        saveBonus: _rangedSaveBonus(target),
        autoHit: auto,
        rerollFirstMiss: progress.reroll,
      ));
      _afterRangedAttack(target, outcome, progress);
      _report(squad, target, weapon, outcome, events);
    }
    progress.actionTaken = true;
    _endActivation(events);
  }

  void _scatterShot(Squad squad, Weapon weapon, Vec2? aimed,
      ActivationProgress progress, List<GameEvent> events) {
    final point = aimed ??
        (throw const RuleViolation(ViolationCode.objetivoRequerido));
    if (progress.moved) {
      throw const RuleViolation(ViolationCode.movioAntesDeDisparar);
    }
    final reach = squad.alive
        .map((s) => s.position.distanceTo(point) - s.baseRadius)
        .reduce(math.min);
    if (reach > weapon.range + _epsilon) {
      throw const RuleViolation(ViolationCode.fueraDeAlcance);
    }
    if (!field.isPointVisible(squad, point)) {
      throw const RuleViolation(ViolationCode.sinVision);
    }

    final accuracy = _dice.d6();
    var landed = point;
    if (accuracy < 4) {
      // Se desvía tantas pulgadas como el resultado, en una de 36 direcciones.
      final a = _dice.d6();
      final b = _dice.d6();
      final angle = ((a - 1) * 6 + (b - 1)) * (2 * math.pi / 36);
      landed = field.clampToBoard(
          point + Vec2(math.cos(angle), math.sin(angle)) * accuracy.toDouble());
    }
    events.add(ScatterResolved(
        squadId: squad.id, aimed: point, landed: landed, accuracyRoll: accuracy));

    for (final target in state.squads) {
      if (target.destroyed) continue;
      final caught = target.alive
          .where((s) =>
              s.position.distanceTo(landed) - s.baseRadius <=
              scatterRadius + _epsilon)
          .length;
      if (caught == 0) continue;
      final outcome = _combat.resolve(AttackSpec(
        target: target,
        attackCount: caught,
        hitTarget: 7,
        strength: weapon.strength,
        ap: weapon.ap,
        damage: weapon.damage,
        woundModifier: progress.focusedFire && target.shotAtThisRound ? 1 : 0,
        saveBonus: _rangedSaveBonus(target),
        autoHit: true,
      ));
      _afterRangedAttack(target, outcome, progress);
      _report(squad, target, weapon, outcome, events);
    }
  }

  void _charge(Charge c, List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    _requireNotRetreated(progress);
    _requireNotEngaged(squad);
    if (squad.demoralized) {
      throw const RuleViolation(ViolationCode.desmoralizada);
    }
    final target = _enemySquad(squad, c.targetSquadId);
    if (field.distance(squad, target) > chargeRange + _epsilon) {
      throw const RuleViolation(ViolationCode.fueraDeAlcance);
    }
    final distance = squad.profile.has(Abilities.asalto)
        ? assaultChargeDistance
        : chargeDistance;
    _validateDestinations(squad, c.destinations, distance);
    final projected = _projected(squad, c.destinations);
    if (minEdgeDistance(projected.values, target.discs) > contactTolerance) {
      throw const RuleViolation(ViolationCode.cargaSinContacto);
    }

    _applyPositions(squad, c.destinations);
    events.add(SquadMoved(squad.id, kind: 'charge'));
    _triggerOverwatch(squad, events);
    if (squad.destroyed) {
      progress.actionTaken = true;
      _endActivation(events);
      return;
    }
    squad.engagedWith.add(target.id);
    target.engagedWith.add(squad.id);
    events.add(ChargeMade(squad.id, target.id));
    final counter = target.counterAttack;
    target.counterAttack = false;
    _melee(
        attacker: squad,
        defender: target,
        charged: true,
        defenderFirst: counter,
        events: events);
    progress.actionTaken = true;
    _endActivation(events);
  }

  void _fight(Fight c, List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    if (progress.retreated) {
      throw const RuleViolation(ViolationCode.accionYaRealizada);
    }
    if (!squad.engagedWith.contains(c.targetSquadId)) {
      throw const RuleViolation(ViolationCode.noTrabada);
    }
    final target = _enemySquad(squad, c.targetSquadId);
    _melee(attacker: squad, defender: target, charged: false, events: events);
    progress.actionTaken = true;
    _endActivation(events);
  }

  void _secure(List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    _requireNotRetreated(progress);
    if (squad.demoralized) {
      throw const RuleViolation(ViolationCode.desmoralizada);
    }
    if (!field.isNearAnyObjective(squad)) {
      throw const RuleViolation(ViolationCode.lejosDeObjetivo);
    }
    squad.securing = true;
    progress.actionTaken = true;
    events.add(SquadSecuring(squad.id));
    _endActivation(events);
  }

  void _entrench(List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    _requireNotEngaged(squad);
    if (progress.moved) throw const RuleViolation(ViolationCode.yaMovio);
    squad.entrenched = true;
    progress.actionTaken = true;
    events.add(SquadEntrenched(squad.id));
    _endActivation(events);
  }

  void _run(Run c, List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    _requireNotEngaged(squad);
    _requireNotRetreated(progress);
    _validateDestinations(squad, c.destinations, _baseMovement(squad));
    _applyPositions(squad, c.destinations);
    progress.actionTaken = true;
    events.add(SquadMoved(squad.id, kind: 'run'));
    _triggerOverwatch(squad, events);
    _endActivation(events);
  }

  void _playOrder(PlayOrder c, List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    final side = squad.side;
    final order = c.order;
    if (!state.hands[side]!.contains(order)) {
      throw RuleViolation(ViolationCode.ordenNoDisponible, order.id);
    }
    if (state.commandPoints[side]! < order.cost) {
      throw const RuleViolation(ViolationCode.puntosDeMandoInsuficientes);
    }
    _requireNoAction(progress);
    if (order == OrderType.avanceForzado && progress.moved) {
      throw const RuleViolation(ViolationCode.ordenFueraDeMomento);
    }

    var target = squad;
    if (order.target != OrderTarget.activa) {
      final id = c.targetSquadId ??
          (throw const RuleViolation(ViolationCode.ordenSinObjetivo));
      target = _squad(id);
      if (target.side != side || target.destroyed) {
        throw const RuleViolation(ViolationCode.ordenSinObjetivo);
      }
      if (order.target == OrderTarget.propiaDesmoralizada &&
          !target.demoralized) {
        throw const RuleViolation(ViolationCode.ordenSinObjetivo);
      }
    }

    switch (order) {
      case OrderType.repetid:
        progress.reroll = true;
      case OrderType.avanceForzado:
        progress.extraMove += forcedMarchBonus;
      case OrderType.cuerpoATierra:
        target.takingCover = true;
      case OrderType.arenga:
        target.demoralized = false;
      case OrderType.fuegoCobertura:
        progress.coveringFire = true;
      case OrderType.contraataque:
        target.counterAttack = true;
      case OrderType.fuegoConcentrado:
        progress.focusedFire = true;
      case OrderType.doblePaso:
        progress.doubleStep = true;
    }
    state.hands[side]!.remove(order);
    state.commandPoints[side] = state.commandPoints[side]! - order.cost;
    events.add(OrderPlayed(side, order, target.id, state.commandPoints[side]!));
  }

  void _fortify(Fortify c, List<GameEvent> events) {
    final squad = _activeSquad();
    final progress = state.progress!;
    _requireNoAction(progress);
    _requireNotRetreated(progress);
    _requireNotEngaged(squad);
    if (!squad.profile.has(Abilities.fortificar)) {
      throw const RuleViolation(ViolationCode.sinHabilidad);
    }
    final reach = squad.alive
        .map((s) => s.position.distanceTo(c.center) - s.baseRadius)
        .reduce(math.min);
    if (reach > fortifyReach + _epsilon) {
      throw const RuleViolation(ViolationCode.fueraDeAlcance);
    }
    final w = c.vertical ? parapetDepth : parapetLength;
    final h = c.vertical ? parapetLength : parapetDepth;
    final x = c.center.x - w / 2;
    final y = c.center.y - h / 2;
    final board = state.board;
    if (x < 0 || y < 0 || x + w > board.width || y + h > board.height) {
      throw const RuleViolation(ViolationCode.fueraDelTablero);
    }
    final area = TerrainArea(
      id: 'parapeto_${state.fortifications.length + 1}',
      type: TerrainType.muroBajo,
      polygon: Polygon.rect(x, y, w, h),
    );
    state.fortifications.add(area);
    progress.actionTaken = true;
    events.add(Fortified(squad.id, area.id));
    _endActivation(events);
  }

  // ------------------------------------------------------------ combate

  void _melee({
    required Squad attacker,
    required Squad defender,
    required bool charged,
    required List<GameEvent> events,
    bool defenderFirst = false,
  }) {
    final bonus =
        charged && attacker.profile.has(Abilities.cargaDevastadora) ? 1 : 0;
    if (defenderFirst) {
      _strike(defender, attacker, 0, events);
      if (!attacker.destroyed && !defender.destroyed) {
        _strike(attacker, defender, bonus, events);
      }
      return;
    }
    _strike(attacker, defender, bonus, events);
    if (!defender.destroyed && !attacker.destroyed) {
      _strike(defender, attacker, 0, events);
    }
  }

  int _rangedSaveBonus(Squad target) =>
      (target.entrenched ? 1 : 0) + (target.takingCover ? 1 : 0);

  void _afterRangedAttack(
      Squad target, AttackOutcome outcome, ActivationProgress progress) {
    target
      ..takingCover = false
      ..shotAtThisRound = true;
    if (progress.coveringFire && outcome.hits > 0 && !target.destroyed) {
      target.suppressed = true;
    }
  }

  void _strike(Squad from, Squad to, int strengthBonus, List<GameEvent> events) {
    final weapon = from.profile.meleeWeapon;
    final outcome = _combat.resolve(AttackSpec(
      target: to,
      attackCount: from.aliveCount * weapon.attacks,
      hitTarget: weapon.meleeHit!,
      hitModifier: clampModifier(from.demoralized ? -1 : 0),
      strength: weapon.strength + strengthBonus,
      ap: weapon.ap,
      damage: weapon.damage,
      saveBonus: to.entrenched ? 1 : 0,
    ));
    _report(from, to, weapon, outcome, events);
  }

  int _shootingModifier(Squad attacker, Squad target,
      ActivationProgress progress,
      {required bool ignoreCover}) {
    var mod = 0;
    if (attacker.demoralized) mod -= 1;
    if (!ignoreCover && field.inCover(attacker, target)) mod -= 1;
    if (attacker.upperFloor && !target.upperFloor) mod += 1;
    if (attacker.profile.has(Abilities.firmes) && !progress.moved) mod += 1;
    return clampModifier(mod);
  }

  void _report(Squad attacker, Squad target, Weapon weapon,
      AttackOutcome outcome, List<GameEvent> events,
      {bool reaction = false}) {
    events.add(AttackResolved(
      attackerId: attacker.id,
      targetId: target.id,
      weaponId: weapon.id,
      dice: outcome.dice,
      hits: outcome.hits,
      wounds: outcome.wounds,
      unsaved: outcome.unsaved,
      killed: outcome.killed,
      rolls: outcome.rolls,
      reaction: reaction,
    ));
    if (outcome.killed > 0) _lostThisActivation.add(target.id);
    if (target.destroyed && outcome.killed > 0) {
      if (attacker.side != target.side) attacker.squadsDestroyed++;
      for (final otherId in target.engagedWith.toList()) {
        state.squadById(otherId).engagedWith.remove(target.id);
      }
      target.engagedWith.clear();
      events.add(SquadDestroyed(target.id, attacker.id));
    }
  }

  // -------------------------------------------------------- flujo de ronda

  void _beginRound(List<GameEvent> events) {
    state.step = BattleStep.mando;
    events.add(RoundStarted(state.round));
    for (final squad in state.squads) {
      squad
        ..activatedThisRound = false
        ..securing = false
        ..shotAtThisRound = false;
    }

    for (final side in Side.values) {
      final gained = 1 + (_hasCaptain(side) ? 1 : 0);
      final total = math.min(BattleState.maxCommandPoints,
          state.commandPoints[side]! + gained);
      state.commandPoints[side] = total;
      events.add(CommandPointsGained(side, gained, total));
    }

    for (final squad in state.squads) {
      if (squad.destroyed || !squad.demoralized) continue;
      final roll = _dice.d6() + _dice.d6();
      final success = roll <= _effectiveMorale(squad);
      if (success) squad.demoralized = false;
      events.add(SquadRallied(squad.id, roll, success: success));
    }

    final initiative = _decideInitiative();
    events.add(InitiativeDecided(initiative));
    state.step = BattleStep.activaciones;
    state.activeSide = initiative;
    if (!_hasAvailable(initiative)) _advanceTurn(events);
  }

  Side _decideInitiative() {
    final j = state.victoryPoints[Side.jugador]!;
    final e = state.victoryPoints[Side.enemigo]!;
    if (j != e) return j < e ? Side.jugador : Side.enemigo;
    while (true) {
      final rj = _dice.d6();
      final re = _dice.d6();
      if (rj != re) return rj > re ? Side.jugador : Side.enemigo;
    }
  }

  void _endActivation(List<GameEvent> events) {
    final squad = _activeSquad();
    final doubleStep = state.progress?.doubleStep ?? false;
    squad
      ..activatedThisRound = true
      ..suppressed = false;

    for (final id in _lostThisActivation) {
      final s = state.squadById(id);
      if (s.destroyed || s.demoralized || !s.belowHalf) continue;
      final morale = _effectiveMorale(s);
      final roll = _dice.d6() + _dice.d6();
      final passed = roll <= morale;
      if (!passed) s.demoralized = true;
      events.add(MoraleChecked(s.id, roll, morale, passed: passed));
    }
    _lostThisActivation.clear();

    state.activeSquadId = null;
    state.progress = null;
    events.add(ActivationEnded(squad.id));
    state.mission.afterActivation(state, field, events);

    if (_checkElimination(events)) return;
    _advanceTurn(events, keepSide: doubleStep);
  }

  void _advanceTurn(List<GameEvent> events, {bool keepSide = false}) {
    final current = state.activeSide!;
    final other = current.opponent;
    if (keepSide && _hasAvailable(current)) {
      state.activeSide = current;
    } else if (_hasAvailable(other)) {
      state.activeSide = other;
    } else if (_hasAvailable(current)) {
      state.activeSide = current;
    } else {
      _scoring(events);
      return;
    }
    events.add(TurnPassed(state.activeSide!));
  }

  void _scoring(List<GameEvent> events) {
    state.step = BattleStep.puntuacion;
    state.activeSide = null;
    final result = state.mission.score(state, field, events);
    if (result != null) {
      _finish(result.winner, events);
      return;
    }
    if (state.round >= state.maxRounds) {
      _finish(state.mission.byVictoryPoints(state).winner, events);
      return;
    }
    state.round++;
    _beginRound(events);
  }

  bool _checkElimination(List<GameEvent> events) {
    final jAlive = state.aliveSquadsOf(Side.jugador).isNotEmpty;
    final eAlive = state.aliveSquadsOf(Side.enemigo).isNotEmpty;
    if (jAlive && eAlive) return false;
    _finish(jAlive ? Side.jugador : (eAlive ? Side.enemigo : null), events);
    return true;
  }

  void _finish(Side? winner, List<GameEvent> events) {
    state.step = BattleStep.terminada;
    state.activeSide = null;
    state.winner = winner;
    events.add(BattleEnded(winner));
  }

  // ------------------------------------------------------------ apoyo

  /// MOV de la escuadra, con la penalización de Fuego de cobertura.
  double _baseMovement(Squad squad) => math.max(
      0.0,
      squad.profile.stats.mov -
          (squad.suppressed ? suppressionPenalty : 0.0));

  bool _hasAvailable(Side side) =>
      state.aliveSquadsOf(side).any((s) => !s.activatedThisRound);

  bool _hasCaptain(Side side) => state
      .aliveSquadsOf(side)
      .any((s) => s.profile.has(Abilities.vozDeMando));

  /// MOR propia, o 8 si hay una Capitana aliada viva a 6" o menos.
  int _effectiveMorale(Squad squad) {
    final base = squad.profile.stats.mor;
    for (final ally in state.aliveSquadsOf(squad.side)) {
      if (ally.id == squad.id || !ally.profile.has(Abilities.vozDeMando)) {
        continue;
      }
      if (field.distance(ally, squad) <= captainAuraRange + _epsilon) {
        return math.max(base, captainAuraMorale);
      }
    }
    return base;
  }

  Squad _squad(String id) {
    for (final s in state.squads) {
      if (s.id == id) return s;
    }
    throw RuleViolation(ViolationCode.escuadraDesconocida, id);
  }

  Squad _activeSquad() {
    final id = state.activeSquadId;
    if (id == null) throw const RuleViolation(ViolationCode.sinActivacion);
    return state.squadById(id);
  }

  Squad _enemySquad(Squad attacker, String targetId) {
    final target = _squad(targetId);
    if (target.side == attacker.side) {
      throw const RuleViolation(ViolationCode.objetivoNoEnemigo);
    }
    if (target.destroyed) {
      throw const RuleViolation(ViolationCode.escuadraDestruida);
    }
    return target;
  }

  List<Squad> _engagedEnemies(Squad squad) => [
        for (final id in squad.engagedWith) state.squadById(id),
      ];

  void _requireNoAction(ActivationProgress p) {
    if (p.actionTaken) {
      throw const RuleViolation(ViolationCode.accionYaRealizada);
    }
  }

  void _requireNotRetreated(ActivationProgress p) {
    if (p.retreated) {
      throw const RuleViolation(ViolationCode.accionYaRealizada);
    }
  }

  void _requireNotEngaged(Squad squad) {
    if (squad.engagedWith.isNotEmpty) {
      throw const RuleViolation(ViolationCode.trabadaEnCombate);
    }
  }

  /// Peanas vivas de la escuadra con los destinos aplicados.
  Map<String, Disc> _projected(Squad squad, Map<String, Vec2> destinations) => {
        for (final s in squad.alive)
          s.id: (
            center: destinations[s.id] ?? s.position,
            radius: s.baseRadius,
          ),
      };

  void _validateDestinations(
      Squad squad, Map<String, Vec2> destinations, double allowance) {
    for (final entry in destinations.entries) {
      final soldier = squad.soldierById(entry.key) ??
          (throw RuleViolation(ViolationCode.soldadoDesconocido, entry.key));
      if (!soldier.alive) {
        throw RuleViolation(ViolationCode.soldadoEliminado, entry.key);
      }
      if (soldier.position.distanceTo(entry.value) > allowance + _epsilon) {
        throw RuleViolation(ViolationCode.movimientoExcesivo, entry.key);
      }
    }

    final projected = _projected(squad, destinations);
    final board = state.board;
    for (final d in projected.values) {
      if (d.center.x - d.radius < -_epsilon ||
          d.center.y - d.radius < -_epsilon ||
          d.center.x + d.radius > board.width + _epsilon ||
          d.center.y + d.radius > board.height + _epsilon) {
        throw const RuleViolation(ViolationCode.fueraDelTablero);
      }
    }

    final own = projected.values.toList();
    for (var i = 0; i < own.length; i++) {
      for (var j = i + 1; j < own.length; j++) {
        if (_overlaps(own[i], own[j])) {
          throw const RuleViolation(ViolationCode.solapamiento);
        }
      }
      for (final other in state.squads) {
        if (other.id == squad.id) continue;
        for (final d in other.discs) {
          if (_overlaps(own[i], d)) {
            throw const RuleViolation(ViolationCode.solapamiento);
          }
        }
      }
    }

    if (own.length > 1) {
      for (var i = 0; i < own.length; i++) {
        var linked = false;
        for (var j = 0; j < own.length && !linked; j++) {
          if (i != j &&
              edgeDistance(own[i], own[j]) <= coherencyRange + _epsilon) {
            linked = true;
          }
        }
        if (!linked) throw const RuleViolation(ViolationCode.coherencia);
      }
    }
  }

  bool _overlaps(Disc a, Disc b) =>
      a.center.distanceTo(b.center) < a.radius + b.radius - _epsilon;

  void _applyPositions(Squad squad, Map<String, Vec2> destinations) {
    for (final entry in destinations.entries) {
      squad.soldierById(entry.key)!.position = entry.value;
    }
  }
}
