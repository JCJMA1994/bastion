import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bastion/data/game_data.dart';
import 'package:bastion/online/online_client.dart';
import 'package:bastion/online/online_session.dart';
import 'package:bastion/online/turn_watch.dart';
import 'package:bastion_server/bastion_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rules_engine/rules_engine.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Cliente HTTP que llama directamente al handler del servidor, sin red.
http.Client _inProcess(shelf.Handler handler) => MockClient((request) async {
      final response = await handler(shelf.Request(
        request.method,
        request.url,
        body: request.body,
        headers: request.headers,
      ));
      return http.Response(await response.readAsString(), response.statusCode,
          headers: response.headers);
    });

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compañía, despliegue oculto y batalla compartida con el servidor',
      () async {
    final data = await GameData.load();
    Map<String, Object?> read(String f) =>
        jsonDecode(File('../data/$f').readAsStringSync()) as Map<String, Object?>;
    final handler = HttpApi(MatchService(
      catalog: ProfileCatalog.fromJson(read('units.json')),
      maps: MapTemplate.catalogFromJson(read('maps.json')),
      random: math.Random(9),
    )).handler;

    OnlineClient client() =>
        OnlineClient('http://servidor', client: _inProcess(handler));

    final roster = RosterDraft.standard.toJson(data.catalog);
    final hostTicket = await client().create(roster);
    final guestTicket = await client().join(hostTicket.code, roster);
    expect(hostTicket.side, Side.jugador);
    expect(guestTicket.side, Side.enemigo);

    const slow = Duration(hours: 1);
    final host = OnlineSession(
        client: client(), ticket: hostTicket, data: data, pollInterval: slow);
    final guest = OnlineSession(
        client: client(), ticket: guestTicket, data: data, pollInterval: slow);
    await host.poll();
    await guest.poll();
    expect(host.phase, OnlinePhase.despliegue);
    expect(guest.phase, OnlinePhase.despliegue);

    // El rival no se ve durante el despliegue.
    final hostDeployment = host.deployment!;
    final rival = hostDeployment.state.aliveSquadsOf(Side.enemigo).first;
    expect(hostDeployment.isHidden(rival), isTrue);

    // El anfitrión recoloca su primera escuadra y confirma; el invitado
    // acepta el despliegue automático.
    final first = hostDeployment.ownSquads.first;
    hostDeployment
      ..select(first.id)
      ..tapBoard(const Vec2(4, 3));
    expect(hostDeployment.lastError, isNull);
    final placed = hostDeployment.state.squadById(first.id).soldiers.first.position;
    await host.submitDeployment();
    expect(host.phase, OnlinePhase.esperandoDespliegue);
    await guest.submitDeployment();
    await host.poll();
    await guest.poll();
    expect(host.battle, isNotNull);
    expect(guest.battle, isNotNull);
    // Al empezar la batalla, el invitado ve la colocación real del anfitrión.
    expect(guest.battle!.state.squadById(first.id).soldiers.first.position,
        placed);

    // Quien tenga la iniciativa activa una escuadra y termina.
    final mover = host.battle!.isPlayerTurn ? host : guest;
    final waiter = identical(mover, host) ? guest : host;
    final battle = mover.battle!;
    final squad = battle.state
        .aliveSquadsOf(battle.mySide)
        .firstWhere((s) => !s.activatedThisRound);
    battle
      ..select(squad.id)
      ..activateSelected()
      ..endActivation();
    await _settle();
    expect(battle.syncError, isNull);

    await waiter.poll();
    expect(waiter.battle!.engine.history.length, battle.engine.history.length);
    expect(waiter.battle!.state.squadById(squad.id).activatedThisRound, isTrue);
    expect(waiter.battle!.isPlayerTurn, isTrue);

    host.dispose();
    guest.dispose();
  });

  group('avisos de turno', () {
    MatchView view(String status,
            {Side? active, Set<Side> deployed = const {}, int version = 3}) =>
        MatchView(
            status: status,
            version: version,
            commands: const [],
            activeSide: active,
            deployed: deployed);

    test('avisa de desplegar, de jugar y del final', () {
      expect(turnMessage(view('despliegue'), Side.jugador), isNotNull);
      expect(turnMessage(view('despliegue', deployed: {Side.jugador}), Side.jugador),
          isNull);
      expect(turnMessage(view('enCurso', active: Side.jugador), Side.jugador),
          isNotNull);
      expect(turnMessage(view('enCurso', active: Side.enemigo), Side.jugador),
          isNull);
      expect(turnMessage(view('terminada'), Side.enemigo), isNotNull);
    });

    test('no repite el aviso de la misma versión', () {
      expect(
          turnMessage(view('enCurso', active: Side.jugador), Side.jugador,
              lastNotifiedVersion: 3),
          isNull);
    });
  });
}
