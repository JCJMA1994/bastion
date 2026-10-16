import 'package:flutter/foundation.dart';
import 'package:rules_engine/rules_engine.dart';

import '../settings/sounds.dart';
import '../telemetry/telemetry.dart';
import 'board_controller.dart';

/// Envía al servidor los comandos aplicados en local (multijugador).
abstract interface class CommandGateway {
  /// [version] es el número de comandos que había antes de este.
  Future<void> push(int version, Command command);
}

/// Puente entre el motor de reglas y la interfaz. La UI envía comandos y lee
/// el estado; nunca lo modifica directamente.
class BattleController extends BoardController {
  BattleController(
    this.engine, {
    this.ai = const SimpleAi(),
    this.onChanged,
    this.mySide = Side.jugador,
    this.aiEnabled = true,
    this.gateway,
  });

  final BattleEngine engine;
  final SimpleAi ai;

  @override
  final Side mySide;

  /// La IA juega el otro bando (desactivada en multijugador).
  final bool aiEnabled;

  /// Nulo en partidas locales.
  final CommandGateway? gateway;

  /// Error al enviar al servidor; la sesión online se resincroniza.
  Object? syncError;
  Future<void> _pushQueue = Future.value();

  /// Se llama tras cada comando aplicado (para guardar la partida).
  final VoidCallback? onChanged;

  @override
  BattleState get state => engine.state;
  Battlefield get field => engine.field;

  @override
  String? selectedSquadId;
  ViolationCode? lastError;
  final List<GameEvent> log = [];

  /// Eventos del último comando del jugador y de la IA que le siguió, para el
  /// resumen animado de tiradas.
  List<GameEvent> recent = const [];

  /// Contador que cambia con cada nuevo lote de eventos (clave de animación).
  int feedVersion = 0;

  @override
  String? get activeSquadId => state.activeSquadId;

  /// Destinos previstos mientras el jugador arrastra la escuadra activa.
  Map<String, Vec2>? ghost;

  Squad? get selected =>
      selectedSquadId == null ? null : state.squadById(selectedSquadId!);

  Squad? get active =>
      state.activeSquadId == null ? null : state.squadById(state.activeSquadId!);

  bool get isPlayerTurn =>
      state.step == BattleStep.activaciones && state.activeSide == mySide;

  /// La escuadra activa es tuya y aún puede mover.
  bool get canMoveActive =>
      isPlayerTurn && active != null && !(state.progress?.moved ?? true);

  /// Pulgadas que puede mover la escuadra activa en esta activación.
  double get moveAllowance {
    final squad = active;
    final progress = state.progress;
    if (squad == null || progress == null) return 0;
    final penalty = squad.suppressed ? BattleEngine.suppressionPenalty : 0.0;
    return squad.profile.stats.mov + progress.extraMove - penalty;
  }

  /// Escuadra enemiga seleccionada mientras hay una activa tuya.
  Squad? get enemyTarget {
    final target = selected;
    if (active == null || target == null || target.side == active!.side) {
      return null;
    }
    return target.destroyed ? null : target;
  }

  List<OrderType> get hand => state.hands[mySide]!;

  /// Empieza una batalla nueva (llama a `engine.start()`).
  void start() {
    _record([...engine.start(), ..._runAi()]);
    notifyListeners();
  }

  /// Retoma una batalla ya empezada: si le toca al enemigo, juega la IA.
  void attach() {
    _record(_runAi());
    onChanged?.call();
    notifyListeners();
  }

  @override
  void select(String squadId) {
    selectedSquadId = squadId;
    lastError = null;
    notifyListeners();
  }

  void activateSelected() {
    final squad = selected;
    if (squad != null) _send(ActivateSquad(squad.id));
  }

  // ------------------------------------------------------------ movimiento

  void dragActive(Vec2 delta) {
    final squad = active;
    if (squad == null || !canMoveActive) return;
    ghost = Planner.translate(squad, delta);
    notifyListeners();
  }

  void dropActive() {
    final destinations = ghost;
    ghost = null;
    if (destinations == null) {
      notifyListeners();
      return;
    }
    _send(MoveSquad(destinations));
  }

  // --------------------------------------------------------------- acciones

  /// Dispara con la primera arma a distancia al enemigo seleccionado. El
  /// cañón apunta al soldado enemigo más cercano.
  void shoot() {
    final shooter = active;
    final target = enemyTarget;
    if (shooter == null || target == null) return;
    final weapon = shooter.profile.weapons.where((w) => !w.isMelee).firstOrNull;
    if (weapon == null) return;
    if (weapon.mode == HitMode.dispersion) {
      final c = shooter.centroid;
      final aim = target.alive
          .reduce((a, b) =>
              c.distanceTo(a.position) <= c.distanceTo(b.position) ? a : b)
          .position;
      _send(Shoot(weaponId: weapon.id, targetPoint: aim));
    } else {
      _send(Shoot(weaponId: weapon.id, targetSquadId: target.id));
    }
  }

  void charge() {
    final attacker = active;
    final target = enemyTarget;
    if (attacker == null || target == null) return;
    final distance = attacker.profile.has(Abilities.asalto)
        ? BattleEngine.assaultChargeDistance
        : BattleEngine.chargeDistance;
    final plan = Planner.charge(state, attacker, target, distance: distance);
    if (plan == null) {
      lastError = ViolationCode.cargaSinContacto;
      notifyListeners();
      return;
    }
    _send(Charge(targetSquadId: target.id, destinations: plan));
  }

  void fight() {
    final squad = active;
    if (squad == null || squad.engagedWith.isEmpty) return;
    _send(Fight(squad.engagedWith.first));
  }

  /// Se puede deshacer el movimiento de la escuadra activa.
  bool get canUndo {
    final p = state.progress;
    return isPlayerTurn &&
        p != null &&
        p.moved &&
        !p.actionTaken &&
        p.undoPositions != null;
  }

  void undoMove() => _send(const UndoMove());

  /// La escuadra activa tiene un arma con la que vigilar.
  bool get canOverwatch {
    final squad = active;
    return squad != null &&
        squad.engagedWith.isEmpty &&
        squad.profile.weapons
            .any((w) => !w.isMelee && w.mode != HitMode.dispersion);
  }

  void overwatch() => _send(const Overwatch());

  /// Arma a distancia con la que dispararía la escuadra activa.
  Weapon? get activeWeapon =>
      active?.profile.weapons.where((w) => !w.isMelee).firstOrNull;

  /// Probabilidades de disparar al enemigo seleccionado.
  AttackOdds? get shotOdds {
    final shooter = active;
    final target = enemyTarget;
    final weapon = activeWeapon;
    if (shooter == null || target == null || weapon == null) return null;
    return engine.previewShot(shooter.id, target.id, weapon.id);
  }

  /// Probabilidades del golpe de carga al enemigo seleccionado.
  AttackOdds? get chargeOdds {
    final attacker = active;
    final target = enemyTarget;
    if (attacker == null || target == null) return null;
    return engine.previewMelee(attacker.id, target.id, charging: true);
  }

  void secure() => _send(const Secure());
  void entrench() => _send(const Entrench());
  void endActivation() => _send(const EndActivation());

  /// Coloca un parapeto 2" por delante de la escuadra, de cara al enemigo.
  void fortify() {
    final squad = active;
    if (squad == null) return;
    final c = squad.centroid;
    final ahead = squad.side == Side.jugador ? 2.0 : -2.0; // hacia el rival
    _send(Fortify(Vec2(c.x + ahead, c.y), vertical: true));
  }

  /// Juega una orden. Las que preparan una escuadra usan la escuadra propia
  /// seleccionada, o la activa si no hay otra.
  void playOrder(OrderType order) {
    final squad = active;
    if (squad == null) return;
    String? target;
    if (order.target != OrderTarget.activa) {
      final own = selected;
      target = own != null && own.side == squad.side ? own.id : squad.id;
    }
    _send(PlayOrder(order, targetSquadId: target));
  }

  bool canAfford(OrderType order) =>
      state.commandPoints[mySide]! >= order.cost;

  // ------------------------------------------------------------------ flujo

  /// Mueve la escuadra activa hacia [target] tanto como pueda (para quien
  /// no puede arrastrar, por ejemplo con lector de pantalla).
  void moveToward(Vec2 target) {
    final squad = active;
    if (squad == null || !canMoveActive) return;
    final c = squad.centroid;
    final full = Planner.stepToward(c, target, moveAllowance) - c;
    for (final fraction in const [1.0, 0.75, 0.5, 0.25]) {
      final delta = full * fraction;
      if (delta.length < 0.25) break;
      try {
        final command = MoveSquad(Planner.translate(squad, delta));
        final events = engine.apply(command);
        lastError = null;
        _afterApplied(command, events);
        return;
      } on RuleViolation catch (violation) {
        lastError = violation.code;
      }
    }
    notifyListeners();
  }

  /// Aplica comandos llegados del servidor (turno del rival).
  void applyRemote(List<Command> commands) {
    final events = <GameEvent>[];
    for (final c in commands) {
      events.addAll(engine.apply(c));
    }
    if (events.isNotEmpty) {
      _record(events);
      _playSounds(events);
      notifyListeners();
    }
  }

  void _send(Command command) {
    try {
      final events = engine.apply(command);
      lastError = null;
      _afterApplied(command, events);
    } on RuleViolation catch (violation) {
      lastError = violation.code;
      Telemetry.instance.debug('rule', 'Comando rechazado',
          data: {'command': command.toJson()['type'], 'code': violation.code.name});
      notifyListeners();
    }
  }

  void _afterApplied(Command command, List<GameEvent> events) {
    final g = gateway;
    if (g != null) {
      final version = engine.history.length - 1;
      _pushQueue = _pushQueue.then((_) => g.push(version, command)).catchError(
          (Object error) {
        syncError = error;
        Telemetry.instance.warning('online_sync', 'Fallo al enviar un comando: $error',
            data: {'version': version});
        notifyListeners();
      });
    }
    for (final e in events.whereType<OrderPlayed>()) {
      Telemetry.instance.event('order_played', {'order': e.order.id});
    }
    final aiEvents = _runAi();
    final all = [...events, ...aiEvents];
    _record(all);
    _playSounds(all);
    onChanged?.call();
    notifyListeners();
  }

  void _playSounds(List<GameEvent> events) {
    var delay = 0;
    var objectiveSounded = false;
    final step = animationFactor == 0 ? 0 : (300 / animationFactor).round();
    for (final e in events) {
      switch (e) {
        case AttackResolved a:
          Sounds.instance.play(a.dice > 0 ? Sfx.dice : Sfx.shot,
              delay: Duration(milliseconds: delay));
          delay += step;
        case ScatterResolved _:
          Sounds.instance.play(Sfx.cannon, delay: Duration(milliseconds: delay));
          delay += step;
        case ChargeMade _:
          Sounds.instance.play(Sfx.charge, delay: Duration(milliseconds: delay));
          delay += step;
        case OrderPlayed _:
          Sounds.instance.play(Sfx.order, delay: Duration(milliseconds: delay));
        case MoraleChecked m when !m.passed:
          Sounds.instance.play(Sfx.morale, delay: Duration(milliseconds: delay));
          delay += step;
        case ObjectiveScored o when o.side == mySide && !objectiveSounded:
          objectiveSounded = true;
          Sounds.instance.play(Sfx.objective, delay: Duration(milliseconds: delay));
        case BattleEnded b:
          Sounds.instance.play(b.winner == mySide ? Sfx.victory : Sfx.defeat,
              delay: Duration(milliseconds: delay));
        default:
          break;
      }
    }
  }

  void _record(List<GameEvent> events) {
    log.addAll(events);
    if (events.any((e) =>
        e is AttackResolved || e is ScatterResolved || e is MoraleChecked)) {
      recent = events;
      feedVersion++;
    }
  }

  List<GameEvent> _runAi() {
    final events = <GameEvent>[];
    var guard = 0;
    final aiSide = mySide.opponent;
    while (aiEnabled &&
        state.step == BattleStep.activaciones &&
        state.activeSide == aiSide &&
        guard++ < 100) {
      events.addAll(ai.playActivation(engine, aiSide));
    }
    return events;
  }
}
