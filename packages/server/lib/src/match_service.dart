import 'dart:math' as math;

import 'package:rules_engine/rules_engine.dart';

import 'match_storage.dart';
import 'turn_notifier.dart';

enum MatchStatus { esperando, despliegue, enCurso, terminada }

/// Error de la API con su código HTTP y un código legible por la app.
final class MatchError implements Exception {
  const MatchError(this.status, this.code);

  final int status;
  final String code;

  @override
  String toString() => 'MatchError($status, $code)';
}

/// Escuadras y órdenes con las que un jugador entra en la partida.
final class Roster {
  const Roster({required this.squads, required this.hand});

  /// Valida el JSON recibido contra el catálogo: 1 a 4 escuadras, perfiles
  /// únicos una sola vez, coste total dentro de [budget] y hasta [maxHand]
  /// órdenes.
  factory Roster.fromJson(Object? json, ProfileCatalog catalog,
      {int budget = 1 << 30, int maxHand = 5}) {
    if (json is! Map<String, Object?>) throw const MatchError(400, 'roster');
    final squads = json['squads'];
    if (squads is! List<Object?> || squads.isEmpty || squads.length > 4) {
      throw const MatchError(400, 'roster_squads');
    }
    final parsed = <(String, int)>[];
    for (final s in squads) {
      if (s is! Map<String, Object?>) throw const MatchError(400, 'roster');
      final id = s['profile'];
      final soldiers = s['soldiers'];
      if (id is! String || soldiers is! int) {
        throw const MatchError(400, 'roster');
      }
      final UnitProfile profile;
      try {
        profile = catalog[id];
      } on ArgumentError {
        throw const MatchError(400, 'roster_profile');
      }
      if (soldiers < 1 || soldiers > profile.soldiers) {
        throw const MatchError(400, 'roster_soldiers');
      }
      parsed.add((id, soldiers));
    }
    var cost = 0;
    final uniques = <String>{};
    for (final (id, _) in parsed) {
      final profile = catalog[id];
      if (profile.unique && !uniques.add(id)) {
        throw const MatchError(400, 'roster_unique');
      }
      cost += profile.cost ?? 0;
    }
    if (cost > budget) throw const MatchError(400, 'roster_budget');
    final hand = <OrderType>[];
    for (final o in (json['hand'] as List<Object?>?) ?? const []) {
      try {
        hand.add(OrderType.byId(o! as String));
      } on Object {
        throw const MatchError(400, 'roster_hand');
      }
    }
    if (hand.length > maxHand || hand.toSet().length != hand.length) {
      throw const MatchError(400, 'roster_hand');
    }
    return Roster(squads: parsed, hand: hand);
  }

  final List<(String profileId, int soldiers)> squads;
  final List<OrderType> hand;

  Map<String, Object?> toJson() => {
        'squads': [
          for (final (id, soldiers) in squads) {'profile': id, 'soldiers': soldiers},
        ],
        'hand': [for (final o in hand) o.id],
      };
}

final class OnlineMatch {
  OnlineMatch({
    required this.code,
    required this.seed,
    required this.mapId,
    required this.missionId,
    required this.hostToken,
    required this.host,
    this.guestToken,
    this.guest,
    this.session,
    this.pendingSetup,
    this.pendingState,
    Set<Side>? deployed,
  }) : deployed = deployed ?? {};

  final String code;
  final int seed;
  final String mapId;
  final String missionId;
  final String hostToken;
  final Roster host;
  String? guestToken;
  Roster? guest;
  BattleSession? session;

  /// Fase de despliegue: configuración y estado antes de empezar.
  BattleSetup? pendingSetup;
  BattleState? pendingState;

  /// Bandos que ya confirmaron su despliegue.
  final Set<Side> deployed;

  MatchStatus get status {
    final s = session;
    if (s == null) {
      return pendingSetup == null ? MatchStatus.esperando : MatchStatus.despliegue;
    }
    return s.engine.state.step == BattleStep.terminada
        ? MatchStatus.terminada
        : MatchStatus.enCurso;
  }

  /// El anfitrión juega el bando jugador; el invitado, el enemigo.
  Side? sideOf(String? token) {
    if (token == null) return null;
    if (token == hostToken) return Side.jugador;
    if (token == guestToken) return Side.enemigo;
    return null;
  }
}

/// Lógica de las partidas, independiente de HTTP.
final class MatchService {
  MatchService({
    required this.catalog,
    required this.maps,
    this.storage,
    this.notifier,
    this.budget = defaultBudget,
    math.Random? random,
  }) : _random = random ?? math.Random.secure();

  /// Presupuesto de una compañía multijugador (la Capitana no cuenta).
  static const defaultBudget = 150;
  static const maxHand = 3;

  final ProfileCatalog catalog;
  final Map<String, MapTemplate> maps;
  final MatchStorage? storage;
  final TurnNotifier? notifier;
  final int budget;
  final math.Random _random;
  final Map<String, OnlineMatch> _matches = {};

  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  int get matchCount => _matches.length;

  /// Recupera las partidas guardadas rejugando sus comandos.
  void restore() {
    final s = storage;
    if (s == null) return;
    for (final json in s.loadAll()) {
      try {
        final match = OnlineMatch(
          code: json['code']! as String,
          seed: (json['seed']! as num).toInt(),
          mapId: json['map']! as String,
          missionId: json['mission']! as String,
          hostToken: json['hostToken']! as String,
          host: _roster(json['host']),
          guestToken: json['guestToken'] as String?,
          guest: json['guest'] == null ? null : _roster(json['guest']),
          deployed: {
            for (final s in (json['deployed'] as List<Object?>?) ?? const [])
              Side.values.byName(s! as String),
          },
          session: json['session'] == null
              ? null
              : BattleSession.restore(
                  json['session']! as Map<String, Object?>, catalog, maps),
        );
        final pending = json['pending'] as Map<String, Object?>?;
        if (match.session == null && pending != null) {
          final setup = BattleSetup.fromJson(pending);
          match
            ..pendingSetup = setup
            ..pendingState = setup.buildState(catalog, maps);
        }
        _matches[match.code] = match;
      } on Object {
        // Una partida corrupta no impide arrancar el servidor.
      }
    }
  }

  /// Crea una partida y devuelve su código y el token del anfitrión.
  Map<String, Object?> create(
      {required String mapId, required String missionId, required Object? roster}) {
    final template = maps[mapId];
    if (template == null) throw const MatchError(400, 'map');
    try {
      missionFromId(missionId);
    } on ArgumentError {
      throw const MatchError(400, 'mission');
    }
    final match = OnlineMatch(
      code: _newCode(),
      seed: _random.nextInt(1 << 30),
      mapId: mapId,
      missionId: missionId,
      hostToken: _newToken(),
      host: _roster(roster),
    );
    _matches[match.code] = match;
    _save(match);
    return {'code': match.code, 'token': match.hostToken, 'side': Side.jugador.name};
  }

  /// Une al invitado y abre la fase de despliegue. Cada bando parte de un
  /// despliegue automático que puede recolocar con [deploy].
  Map<String, Object?> join(String code, {required Object? roster}) {
    final match = _match(code);
    if (match.guestToken != null) throw const MatchError(409, 'full');
    final guest = _roster(roster);
    final setup = BattleSetup(
      seed: match.seed,
      mapId: match.mapId,
      missionId: match.missionId,
      squads: [
        for (final (i, (id, soldiers)) in match.host.squads.indexed)
          SquadSetup(id: 'h${i + 1}', side: Side.jugador, profileId: id, soldiers: soldiers),
        for (final (i, (id, soldiers)) in guest.squads.indexed)
          SquadSetup(id: 'g${i + 1}', side: Side.enemigo, profileId: id, soldiers: soldiers),
      ],
      hands: {Side.jugador: match.host.hand, Side.enemigo: guest.hand},
    );
    match
      ..guest = guest
      ..guestToken = _newToken()
      ..pendingSetup = setup
      ..pendingState = setup.buildState(catalog, maps);
    _save(match);
    notifier?.yourTurn(match.code, Side.jugador, reason: 'despliegue');
    return {'code': match.code, 'token': match.guestToken, 'side': Side.enemigo.name};
  }

  /// Confirma el despliegue de un bando. [centers] coloca cada escuadra
  /// propia en formación en ese punto (`{squadId: {x, y}}`); las que no
  /// aparecen se quedan donde las dejó el despliegue automático. Cuando los
  /// dos bandos confirman, empieza la batalla.
  Map<String, Object?> deploy(String code, String? token, {required Object? centers}) {
    final match = _match(code);
    final side = match.sideOf(token) ?? (throw const MatchError(403, 'token'));
    final state = match.pendingState;
    if (state == null) throw const MatchError(409, 'not_deploying');
    if (match.deployed.contains(side)) throw const MatchError(409, 'already_deployed');
    if (centers is! Map<String, Object?>) throw const MatchError(400, 'centers');

    final own = state.squads.where((s) => s.side == side).toList();
    final snapshot = {
      for (final s in own) s.id: [for (final p in s.soldiers) p.position],
    };
    final deployment = Deployment(state);
    try {
      for (final entry in centers.entries) {
        final squad = own.where((s) => s.id == entry.key).firstOrNull ??
            (throw const MatchError(400, 'centers'));
        final point = entry.value;
        if (point is! Map<String, Object?>) throw const MatchError(400, 'centers');
        deployment.place(squad, Vec2.fromJson(point));
      }
    } on Object catch (error) {
      // Nada a medias: se restauran las posiciones anteriores.
      for (final s in own) {
        final before = snapshot[s.id]!;
        for (var i = 0; i < s.soldiers.length; i++) {
          s.soldiers[i].position = before[i];
        }
      }
      if (error is RuleViolation) throw MatchError(422, error.code.name);
      if (error is MatchError) rethrow;
      throw const MatchError(400, 'centers');
    }

    match.deployed.add(side);
    if (match.deployed.length == 2) {
      match
        ..session = BattleSession.begin(setup: match.pendingSetup!, deployedState: state)
        ..pendingSetup = null
        ..pendingState = null;
      final first = match.session!.engine.state.activeSide;
      if (first != null) notifier?.yourTurn(match.code, first, reason: 'turno');
    }
    _save(match);
    return {'status': match.status.name};
  }

  /// Estado de la partida para un jugador: configuración y comandos desde
  /// [since].
  Map<String, Object?> view(String code, String? token, {int since = 0}) {
    final match = _match(code);
    final side = match.sideOf(token) ?? (throw const MatchError(403, 'token'));
    final session = match.session;
    final history = session?.engine.history ?? const <Command>[];
    final from = since.clamp(0, history.length);
    final pending = match.pendingSetup;
    return {
      'code': match.code,
      'status': match.status.name,
      'side': side.name,
      'version': history.length,
      if (session != null) 'setup': session.setup.toJson(),
      if (pending != null) ...{
        'setup': _hideOpponent(
                pending.withPositionsFrom(match.pendingState!), side)
            .toJson(),
        'deployed': [for (final s in match.deployed) s.name],
      },
      if (session != null) 'activeSide': session.engine.state.activeSide?.name,
      if (session != null) 'winner': session.engine.state.winner?.name,
      'commands': [for (final c in history.skip(from)) c.toJson()],
    };
  }

  /// Aplica un comando del jugador al que le toca. [version] debe coincidir
  /// con los comandos ya aplicados (control de concurrencia optimista).
  Map<String, Object?> submit(String code, String? token,
      {required Object? version, required Object? command}) {
    final match = _match(code);
    final side = match.sideOf(token) ?? (throw const MatchError(403, 'token'));
    final session = match.session ?? (throw const MatchError(409, 'not_started'));
    final engine = session.engine;
    if (engine.state.step == BattleStep.terminada) {
      throw const MatchError(409, 'finished');
    }
    if (version is! int || version != engine.history.length) {
      throw const MatchError(409, 'version');
    }
    if (engine.state.activeSide != side) throw const MatchError(409, 'not_your_turn');
    if (command is! Map<String, Object?>) throw const MatchError(400, 'command');
    final Command parsed;
    try {
      parsed = Command.fromJson(command);
    } on Object {
      throw const MatchError(400, 'command');
    }
    try {
      engine.apply(parsed);
    } on RuleViolation catch (v) {
      throw MatchError(422, v.code.name);
    }
    _save(match);
    final next = engine.state.activeSide;
    if (engine.state.step == BattleStep.terminada) {
      for (final s in Side.values) {
        notifier?.yourTurn(match.code, s, reason: 'fin');
      }
    } else if (next != null && next != side) {
      notifier?.yourTurn(match.code, next, reason: 'turno');
    }
    return {'version': engine.history.length};
  }

  Roster _roster(Object? json) =>
      Roster.fromJson(json, catalog, budget: budget, maxHand: maxHand);

  /// Durante el despliegue, cada jugador no ve dónde coloca el rival.
  static BattleSetup _hideOpponent(BattleSetup setup, Side viewer) => BattleSetup(
        seed: setup.seed,
        mapId: setup.mapId,
        missionId: setup.missionId,
        defender: setup.defender,
        hands: setup.hands,
        squads: [
          for (final s in setup.squads)
            s.side == viewer
                ? s
                : SquadSetup(
                    id: s.id,
                    side: s.side,
                    profileId: s.profileId,
                    soldiers: s.soldiers,
                    rank: s.rank,
                  ),
        ],
      );

  OnlineMatch _match(String code) =>
      _matches[code.toUpperCase()] ?? (throw const MatchError(404, 'match'));

  String _newCode() {
    while (true) {
      final code = String.fromCharCodes([
        for (var i = 0; i < 6; i++)
          _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
      ]);
      if (!_matches.containsKey(code)) return code;
    }
  }

  String _newToken() => [
        for (var i = 0; i < 24; i++) _random.nextInt(16).toRadixString(16),
      ].join();

  void _save(OnlineMatch m) => storage?.save(m.code, {
        'code': m.code,
        'seed': m.seed,
        'map': m.mapId,
        'mission': m.missionId,
        'hostToken': m.hostToken,
        'host': m.host.toJson(),
        'guestToken': m.guestToken,
        'guest': m.guest?.toJson(),
        'session': m.session?.toJson(),
        'pending': m.pendingState == null
            ? null
            : m.pendingSetup!.withPositionsFrom(m.pendingState!).toJson(),
        'deployed': [for (final s in m.deployed) s.name],
      });
}
