import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:rules_engine/rules_engine.dart';

import '../art/art_set.dart';
import '../art/renderers.dart';
import '../data/battle_stats.dart';
import '../data/campaign_repository.dart';
import '../data/game_data.dart';
import '../game/battle_controller.dart';
import '../game/deployment_controller.dart';
import '../online/online_client.dart';
import '../online/online_session.dart';
import '../online/turn_watch.dart';
import '../remote_config/remote_config.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry.dart';

enum AppScreen {
  menu,
  campana,
  compania,
  despliegue,
  batalla,
  resultado,
  encuentro,
  suministros,
  ajustes,
  online,
  registro,
}

/// Navegación del bucle de juego y guardado. Las pantallas leen de aquí y
/// llaman a sus métodos; las reglas siguen en `rules_engine`.
class AppController extends ChangeNotifier {
  AppController(this.data, this.repository, this.settings,
      {math.Random? random,
      this.clientFactory = OnlineClient.new,
      this.turnWatcher = const NoopTurnWatcher(),
      this.stats,
      this.remoteConfig,
      this.logs,
      this.art})
      : _random = random ?? math.Random();

  /// Arte de sprites cargado; nulo si no hay o no se pudo cargar.
  final ArtSet? art;

  /// Renderizadores de la próxima batalla según el ajuste, la configuración
  /// remota y el arte disponible. Sin arte, siempre vectorial.
  Renderers get renderers {
    final chosen = settings.artStyle == ArtStyle.auto
        ? (remoteConfig?.artStyle ?? 'vector')
        : settings.artStyle.name;
    final loaded = art;
    if (chosen == 'sprites' && loaded != null) {
      return Renderers.sprites(loaded, decor: data.decor);
    }
    return const Renderers.vector();
  }

  /// Configuración remota; nula en tests (se usan los valores por defecto).
  final RemoteConfig? remoteConfig;

  /// Registros del dispositivo para el visor; nulo oculta el visor.
  final MemorySink? logs;

  Telemetry get _t => Telemetry.instance;

  bool get multiplayerEnabled => remoteConfig?.multiplayerEnabled ?? true;
  bool get quickBattleEnabled => remoteConfig?.quickBattleEnabled ?? true;
  String get maintenanceMessage => remoteConfig?.maintenanceMessage ?? '';
  bool get updateRequired => remoteConfig?.updateRequired ?? false;

  /// Modo de la batalla en curso, para la analítica.
  String get _battleMode =>
      online != null ? 'online' : (quickBattle ? 'rapida' : 'campana');

  /// Avisos de turno online (en la app real, en segundo plano).
  final TurnWatcher turnWatcher;

  /// Estadísticas de partidas reales; nulas en tests.
  final BattleStats? stats;

  /// Compañía elegida para el multijugador.
  RosterDraft onlineRoster = RosterDraft.standard;

  final GameData data;
  final CampaignRepository repository;
  final SettingsController settings;
  final math.Random _random;

  /// Crea el cliente HTTP (sustituible en tests).
  final OnlineClient Function(String baseUrl) clientFactory;

  OnlineSession? online;
  bool onlineBusy = false;
  String? onlineError;
  AppScreen _beforeSettings = AppScreen.menu;

  AppScreen screen = AppScreen.menu;
  CampaignRun? run;
  BattleSetup? _pendingSetup;
  DeploymentController? deployment;
  BattleController? battle;
  BattleSession? _session;
  BattleReport? report;
  List<AppliedEffect> lastEffects = const [];
  bool quickBattle = false;

  ProfileCatalog get catalog => data.catalog;

  bool get canContinue => run?.status == CampaignStatus.enCurso;

  /// El tutorial se muestra en la primera batalla hasta completarlo o
  /// saltarlo.
  bool get showTutorial => !repository.tutorialDone;

  void finishTutorial() {
    _t.event('tutorial_skip');
    repository.markTutorialDone();
    notifyListeners();
  }

  /// Nombre del mapa de la batalla en curso o en despliegue.
  String get battleTitle {
    final id = _session?.setup.mapId ?? _pendingSetup?.mapId;
    if (id == null) return online == null ? '' : 'Partida ${online!.ticket.code}';
    return data.maps[id]!.name;
  }

  // ------------------------------------------------------------- arranque

  /// Recupera la campaña y, si la había, la batalla en curso.
  void restore() {
    final saved = repository.loadCampaign();
    if (saved != null) {
      try {
        run = CampaignRun.fromJson(saved);
      } on Object catch (e, st) {
        _t.error(e, st, name: 'campaign_restore');
        repository.clearCampaign();
      }
    }
    final savedBattle = repository.loadBattle();
    if (savedBattle != null) {
      try {
        final session =
            BattleSession.restore(savedBattle, data.catalog, data.maps);
        quickBattle = run == null || run!.deployedSquadIds.isEmpty;
        _openBattle(session);
        _t.info('battle_restore', 'Batalla recuperada',
            data: {'commands': session.engine.history.length});
      } on Object catch (e, st) {
        _t.error(e, st, name: 'battle_restore');
        repository.clearBattle();
      }
    }
  }

  // ------------------------------------------------------------- campaña

  void newCampaign() {
    run = CampaignRun.start(
      seed: _random.nextInt(1 << 30),
      catalog: catalog,
      encounterIds: data.encounters.keys.toList(),
      requisas: remoteConfig?.campaignStartingRequisas ??
          CampaignRun.startingRequisas,
    );
    _t.event('campaign_start', {'requisas': run!.requisas});
    _saveCampaign();
    _go(AppScreen.campana);
  }

  void openCampaign() => _go(AppScreen.campana);

  void toMenu() => _go(AppScreen.menu);

  /// Viaja a un nodo y abre la pantalla que le corresponde.
  void travel(String nodeId) {
    final r = run!;
    lastEffects = r.travel(nodeId, catalog);
    final node = r.node(nodeId);
    _t.event('node_travel', {'kind': node.kind.name, 'depth': node.depth, 'day': r.day});
    _saveCampaign();
    _go(switch (r.node(nodeId).kind) {
      NodeKind.batalla || NodeKind.fortin => AppScreen.compania,
      NodeKind.encuentro => AppScreen.encuentro,
      NodeKind.suministros => AppScreen.suministros,
    });
  }

  /// Vuelve a la pantalla pendiente del nodo actual (si se salió a medias).
  void resumeNode() {
    final node = run?.currentNode;
    if (node == null || run!.completed.contains(node.id)) {
      _go(AppScreen.campana);
      return;
    }
    _go(switch (node.kind) {
      NodeKind.batalla || NodeKind.fortin => AppScreen.compania,
      NodeKind.encuentro => AppScreen.encuentro,
      NodeKind.suministros => AppScreen.suministros,
    });
  }

  void chooseEncounterOption(int index) {
    final r = run!;
    final encounter = data.encounters[r.currentNode!.encounterId]!;
    lastEffects = r.resolveEncounter(encounter, index, catalog);
    _t.event('encounter_choice', {'encounter': encounter.id, 'option': index});
    _checkCampaignEnd();
    _saveCampaign();
    notifyListeners();
  }

  void recruit(String profileId) {
    run!.recruit(profileId, catalog);
    _t.event('recruit', {'profile': profileId, 'requisas': run!.requisas});
    _saveCampaign();
    notifyListeners();
  }

  // ------------------------------------------------------------- batalla

  /// Prepara la batalla del nodo actual y abre el despliegue.
  void startDeployment(List<String> squadIds) {
    final setup = run!.prepareBattle(squadIds, catalog);
    quickBattle = false;
    _saveCampaign();
    _openDeployment(setup);
  }

  /// Batalla suelta fuera de campaña, en el molino.
  void startQuickBattle() {
    quickBattle = true;
    _openDeployment(BattleSetup(
      seed: _random.nextInt(1 << 30),
      mapId: 'molino',
      missionId: 'dominio',
      squads: [
        for (final (i, id) in const ['capitana', 'lanceros', 'tiradores', 'canon']
            .indexed)
          SquadSetup(
              id: 'j${i + 1}',
              side: Side.jugador,
              profileId: id,
              soldiers: catalog[id].soldiers),
        for (final (i, id) in const ['lanceros', 'granaderos', 'tiradores']
            .indexed)
          SquadSetup(
              id: 'e${i + 1}',
              side: Side.enemigo,
              profileId: id,
              soldiers: catalog[id].soldiers),
      ],
      hands: {
        Side.jugador: [
          OrderType.avanceForzado,
          OrderType.cuerpoATierra,
          OrderType.fuegoCobertura,
        ],
        Side.enemigo: [OrderType.repetid],
      },
    ));
  }

  void _openDeployment(BattleSetup setup) {
    _pendingSetup = setup;
    deployment = DeploymentController(setup.buildState(catalog, data.maps));
    _go(AppScreen.despliegue);
  }

  void beginBattle() {
    final remote = online;
    if (remote != null) {
      remote.submitDeployment();
      return;
    }
    final session = BattleSession.begin(
        setup: _pendingSetup!, deployedState: deployment!.state);
    _pendingSetup = null;
    deployment = null;
    _openBattle(session);
    notifyListeners();
  }

  void _openBattle(BattleSession session) {
    _session = session;
    battle = BattleController(session.engine,
        ai: SimpleAi(useOrders: remoteConfig?.aiUseOrders ?? true),
        onChanged: () => repository.saveBattle(session.toJson()))
      ..attach();
    _t.event('battle_start', {
      'mode': _battleMode,
      'mission': session.setup.missionId,
      'map': session.setup.mapId,
      'squads': session.setup.squads.where((s) => s.side == Side.jugador).length,
    });
    screen = AppScreen.batalla;
  }

  /// Cierra la batalla terminada y aplica el resultado a la campaña.
  void finishBattle() {
    final state = battle!.state;
    final me = battle!.mySide;
    stats?.record(state, me);
    final own = state.squads.where((s) => s.side == me).toList();
    _t.event('battle_end', {
      'mode': _battleMode,
      'result': state.winner == null
          ? 'tablas'
          : (state.winner == me ? 'victoria' : 'derrota'),
      'rounds': state.round,
      'mission': state.mission.id,
      'profiles': [for (final s in own) s.profile.id],
      'survival': own.isEmpty
          ? 0
          : own.fold<int>(0, (n, s) => n + s.aliveCount) /
              own.fold<int>(0, (n, s) => n + s.startingCount),
    });
    if (online != null) {
      battle = null;
      _closeOnline();
      _go(AppScreen.menu);
      return;
    }
    repository.clearBattle();
    if (showTutorial) repository.markTutorialDone();
    battle = null;
    _session = null;
    if (quickBattle) {
      report = null;
      _go(AppScreen.menu);
      return;
    }
    report = run!.finishBattle(state, catalog);
    _checkCampaignEnd();
    _saveCampaign();
    _go(AppScreen.resultado);
  }

  // ---------------------------------------------------------------- ajustes

  void openLogs() => _go(AppScreen.registro);

  void closeLogs() => _go(AppScreen.ajustes);

  void _checkCampaignEnd() {
    final r = run;
    if (r == null || r.status == CampaignStatus.enCurso) return;
    _t.event('campaign_end', {
      'result': r.status.name,
      'day': r.day,
      'squads': r.squads.length,
    });
  }

  void openSettings() {
    if (screen != AppScreen.ajustes) _beforeSettings = screen;
    _go(AppScreen.ajustes);
  }

  void closeSettings() => _go(_beforeSettings);

  void replayTutorial() {
    repository.resetTutorial();
    notifyListeners();
  }

  // ---------------------------------------------------------- multijugador

  void openOnline() {
    onlineError = null;
    _go(AppScreen.online);
  }

  void setOnlineRoster(RosterDraft roster) {
    onlineRoster = roster;
    notifyListeners();
  }

  Future<void> createOnline() =>
      _connect((client) => client.create(onlineRoster.toJson(catalog)));

  Future<void> joinOnline(String code) {
    if (code.trim().length != 6) {
      onlineError = 'El código tiene 6 caracteres.';
      notifyListeners();
      return Future.value();
    }
    return _connect((client) => client.join(code, onlineRoster.toJson(catalog)));
  }

  Future<void> _connect(
      Future<MatchTicket> Function(OnlineClient client) action) async {
    onlineBusy = true;
    onlineError = null;
    notifyListeners();
    final client = clientFactory(settings.serverUrl);
    try {
      final ticket = await action(client);
      final session = OnlineSession(
        client: client,
        ticket: ticket,
        data: data,
        pollInterval: remoteConfig?.pollInterval ?? const Duration(seconds: 2),
      )..addListener(_onOnlineChanged);
      _t.event('online_connect', {'side': ticket.side.name});
      online = session;
      session.start();
      turnWatcher.watch(settings.serverUrl, ticket);
    } on OnlineError catch (e) {
      client.close();
      _t.warning('online', 'El servidor rechazó la conexión', data: {'code': e.code});
      onlineError = switch (e.code) {
        'match' => 'No existe ninguna partida con ese código.',
        'full' => 'Esa partida ya tiene dos jugadores.',
        'roster_budget' => 'Tu compañía supera los ${RosterDraft.budget} puntos.',
        _ => 'El servidor rechazó la petición (${e.code}).',
      };
    } on Object catch (e) {
      client.close();
      _t.warning('online', 'Sin conexión con el servidor: $e');
      onlineError = 'No se pudo conectar con ${settings.serverUrl}. '
          'Revisa el servidor en Ajustes.';
    } finally {
      onlineBusy = false;
      notifyListeners();
    }
  }

  void _onOnlineChanged() {
    final session = online;
    if (session == null) return;
    final next = session.battle;
    if (next != null && !identical(next, battle)) {
      battle = next;
      deployment = null;
      screen = AppScreen.batalla;
      _t.event('battle_start', {'mode': 'online', 'side': session.ticket.side.name});
    } else if (session.phase == OnlinePhase.despliegue &&
        session.deployment != null &&
        !identical(session.deployment, deployment)) {
      deployment = session.deployment;
      screen = AppScreen.despliegue;
    } else if (session.phase == OnlinePhase.esperandoDespliegue &&
        screen == AppScreen.despliegue) {
      deployment = null;
      screen = AppScreen.online;
    }
    notifyListeners();
  }

  void leaveOnline() {
    _closeOnline();
    _go(AppScreen.menu);
  }

  void _closeOnline() {
    final session = online;
    online = null;
    deployment = null;
    turnWatcher.stop();
    session
      ?..removeListener(_onOnlineChanged)
      ..dispose();
  }

  bool get isOnlineBattle => online != null;

  // --------------------------------------------------------------- apoyo

  String squadLabel(String squadId) {
    final r = run;
    if (r == null) return squadId;
    final s = r.squads.where((q) => q.id == squadId).firstOrNull;
    final profileId = s?.profileId ??
        report?.squads.where((q) => q.squadId == squadId).firstOrNull?.profileId;
    if (profileId == null) return squadId;
    final name = catalog[profileId].name;
    final parts = squadId.split('_');
    final n = int.tryParse(parts.last);
    return n == null || n == 1 ? name : '$name $n';
  }

  void _saveCampaign() {
    final r = run;
    if (r != null) repository.saveCampaign(r.toJson());
  }

  void _go(AppScreen next) {
    if (next != screen) _t.screen(next.name);
    screen = next;
    notifyListeners();
  }
}
