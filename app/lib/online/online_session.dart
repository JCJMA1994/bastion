import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rules_engine/rules_engine.dart';

import '../data/game_data.dart';
import '../game/battle_controller.dart';
import '../game/deployment_controller.dart';
import 'online_client.dart';

enum OnlinePhase {
  /// Esperando a que se una el rival.
  esperandoRival,

  /// Toca desplegar.
  despliegue,

  /// Despliegue enviado; falta el del rival.
  esperandoDespliegue,

  /// Batalla en curso o terminada.
  batalla,
}

/// Partida online: espera al rival, gestiona el despliegue, construye la
/// batalla a partir del servidor, envía los comandos propios y sondea los
/// del rival.
class OnlineSession extends ChangeNotifier implements CommandGateway {
  OnlineSession({
    required this.client,
    required this.ticket,
    required this.data,
    this.pollInterval = const Duration(seconds: 2),
  });

  final OnlineClient client;
  final MatchTicket ticket;
  final GameData data;
  final Duration pollInterval;

  OnlinePhase phase = OnlinePhase.esperandoRival;
  DeploymentController? deployment;
  BattleController? battle;
  Object? error;
  Timer? _timer;
  bool _busy = false;

  bool get waiting => battle == null;

  void start() {
    _timer = Timer.periodic(pollInterval, (_) => poll());
    poll();
  }

  @override
  Future<void> push(int version, Command command) =>
      client.submit(ticket, version, command);

  /// Envía el despliegue actual al servidor.
  Future<void> submitDeployment() async {
    final current = deployment;
    if (current == null) return;
    try {
      await client.deploy(ticket, current.centers);
      deployment = null;
      phase = OnlinePhase.esperandoDespliegue;
      error = null;
    } on Object catch (e) {
      error = e;
    }
    notifyListeners();
    await poll();
  }

  /// Un ciclo de sondeo. Público para poder forzarlo en tests.
  Future<void> poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final current = battle;
      if (current == null || current.syncError != null) {
        await _load();
      } else if (!current.isPlayerTurn &&
          current.state.step != BattleStep.terminada) {
        final view =
            await client.view(ticket, since: current.engine.history.length);
        current.applyRemote(view.commands);
      }
      error = null;
    } on Object catch (e) {
      error = e;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _load() async {
    final view = await client.view(ticket);
    if (view.deploying) {
      if (view.deployed.contains(ticket.side)) {
        deployment = null;
        phase = OnlinePhase.esperandoDespliegue;
      } else if (deployment == null) {
        final state = BattleSetup.fromJson(view.setup!)
            .buildState(data.catalog, data.maps);
        deployment = DeploymentController(state,
            mySide: ticket.side, hideOpponent: true);
        phase = OnlinePhase.despliegue;
      }
      return;
    }
    if (!view.started) return;
    final session = BattleSession.restore({
      'setup': view.setup,
      'commands': [for (final c in view.commands) c.toJson()],
    }, data.catalog, data.maps);
    deployment = null;
    phase = OnlinePhase.batalla;
    battle = BattleController(
      session.engine,
      mySide: ticket.side,
      aiEnabled: false,
      gateway: this,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    client.close();
    super.dispose();
  }
}
