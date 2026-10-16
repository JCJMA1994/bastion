import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bastion_server/bastion_server.dart';
import 'package:rules_engine/rules_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String file) =>
    jsonDecode(File('../../data/$file').readAsStringSync())
        as Map<String, Object?>;

final catalog = ProfileCatalog.fromJson(_json('units.json'));
final maps = MapTemplate.catalogFromJson(_json('maps.json'));

const roster = {
  'squads': [
    {'profile': 'lanceros', 'soldiers': 5},
    {'profile': 'tiradores', 'soldiers': 5},
  ],
  'hand': ['repetid'],
};

MatchService newService([MatchStorage? storage, TurnNotifier? notifier]) =>
    MatchService(
        catalog: catalog,
        maps: maps,
        storage: storage,
        notifier: notifier,
        random: math.Random(1));

/// Crea y une una partida; devuelve el código y el token de cada bando.
(String, Map<String, String>) joinMatch(MatchService service) {
  final host = service.create(mapId: 'molino', missionId: 'dominio', roster: roster);
  final code = host['code']! as String;
  final guest = service.join(code, roster: roster);
  return (
    code,
    {
      'jugador': host['token']! as String,
      'enemigo': guest['token']! as String,
    }
  );
}

/// Como [joinMatch], y los dos bandos aceptan el despliegue automático.
(String, Map<String, String>) startMatch(MatchService service) {
  final (code, tokens) = joinMatch(service);
  service
    ..deploy(code, tokens['jugador'], centers: const <String, Object?>{})
    ..deploy(code, tokens['enemigo'], centers: const <String, Object?>{});
  return (code, tokens);
}

void main() {
  test('al unirse empieza el despliegue; al confirmar ambos, la batalla', () {
    final service = newService();
    final (code, tokens) = joinMatch(service);
    expect(service.view(code, tokens['jugador'])['status'], 'despliegue');
    expect(() => service.join(code, roster: roster),
        throwsA(isA<MatchError>().having((e) => e.code, 'code', 'full')));

    service.deploy(code, tokens['jugador'],
        centers: {'h1': {'x': 4.0, 'y': 3.0}});
    expect(service.view(code, tokens['jugador'])['deployed'], ['jugador']);
    expect(
        () => service.deploy(code, tokens['jugador'], centers: const {}),
        throwsA(isA<MatchError>().having((e) => e.code, 'code', 'already_deployed')));

    service.deploy(code, tokens['enemigo'], centers: const <String, Object?>{});
    final view = service.view(code, tokens['jugador']);
    expect(view['status'], 'enCurso');
    expect(view['version'], 0);
    final setup = BattleSetup.fromJson(view['setup']! as Map<String, Object?>);
    expect(setup.squads.firstWhere((s) => s.id == 'h1').positions!.first.y,
        closeTo(2.25, 1e-9));
  });

  test('durante el despliegue no se ve dónde coloca el rival', () {
    final service = newService();
    final (code, tokens) = joinMatch(service);
    final setup = BattleSetup.fromJson(
        service.view(code, tokens['jugador'])['setup']! as Map<String, Object?>);
    expect(setup.squads.where((s) => s.side == Side.jugador).first.positions,
        isNotNull);
    expect(setup.squads.where((s) => s.side == Side.enemigo).first.positions,
        isNull);
  });

  test('un despliegue fuera de zona se rechaza sin cambiar nada', () {
    final service = newService();
    final (code, tokens) = joinMatch(service);
    String h1() => jsonEncode(
        service.view(code, tokens['jugador'])['setup']);
    final before = h1();
    expect(
      () => service.deploy(code, tokens['jugador'], centers: {
        'h2': {'x': 4.0, 'y': 20.0},
        'h1': {'x': 22.0, 'y': 14.0},
      }),
      throwsA(isA<MatchError>()
          .having((e) => e.code, 'code', ViolationCode.fueraDeZona.name)),
    );
    expect(h1(), before);
  });

  test('las compañías se limitan por presupuesto y perfiles únicos', () {
    final service = newService();
    Object roster(List<String> ids) => {
          'squads': [
            for (final id in ids) {'profile': id, 'soldiers': catalog[id].soldiers},
          ],
        };
    expect(
      () => service.create(
          mapId: 'molino',
          missionId: 'dominio',
          roster: roster(['canon', 'canon', 'batidores'])),
      throwsA(isA<MatchError>().having((e) => e.code, 'code', 'roster_budget')),
    );
    expect(
      () => service.create(
          mapId: 'molino', missionId: 'dominio', roster: roster(['capitana', 'capitana'])),
      throwsA(isA<MatchError>().having((e) => e.code, 'code', 'roster_unique')),
    );
  });

  test('se avisa al jugador al que le toca', () {
    final notifier = RecordingTurnNotifier();
    final service = newService(null, notifier);
    final (code, tokens) = startMatch(service);
    final first = service.view(code, tokens['jugador'])['activeSide']! as String;
    expect(notifier.sent.last.$2.name, first);
    expect(notifier.sent.last.$3, 'turno');

    final squadId = first == 'jugador' ? 'h1' : 'g1';
    service
      ..submit(code, tokens[first],
          version: 0, command: ActivateSquad(squadId).toJson())
      ..submit(code, tokens[first],
          version: 1, command: const EndActivation().toJson());
    expect(notifier.sent.last.$2.name, isNot(first));
  });

  test('solo juega el bando al que le toca y con la versión correcta', () {
    final service = newService();
    final (code, tokens) = startMatch(service);
    final active = service.view(code, tokens['jugador'])['activeSide']! as String;
    final other = active == 'jugador' ? 'enemigo' : 'jugador';
    final squadId = active == 'jugador' ? 'h1' : 'g1';

    expect(
      () => service.submit(code, tokens[other],
          version: 0, command: ActivateSquad(squadId).toJson()),
      throwsA(isA<MatchError>().having((e) => e.code, 'code', 'not_your_turn')),
    );
    expect(
      service.submit(code, tokens[active],
          version: 0, command: ActivateSquad(squadId).toJson()),
      {'version': 1},
    );
    expect(
      () => service.submit(code, tokens[active],
          version: 0, command: const EndActivation().toJson()),
      throwsA(isA<MatchError>().having((e) => e.code, 'code', 'version')),
    );
    expect(
      () => service.submit(code, tokens[active],
          version: 1, command: const Fight('x').toJson()),
      throwsA(isA<MatchError>()
          .having((e) => e.code, 'code', ViolationCode.noTrabada.name)),
    );
  });

  test('un token ajeno no ve la partida', () {
    final service = newService();
    final (code, _) = startMatch(service);
    expect(() => service.view(code, 'intruso'),
        throwsA(isA<MatchError>().having((e) => e.status, 'status', 403)));
  });

  test('las partidas se recuperan del almacenamiento rejugando comandos', () {
    final storage = MemoryMatchStorage();
    final service = newService(storage);
    final (code, tokens) = startMatch(service);
    final active = service.view(code, tokens['jugador'])['activeSide']! as String;
    final squadId = active == 'jugador' ? 'h1' : 'g1';
    service
      ..submit(code, tokens[active],
          version: 0, command: ActivateSquad(squadId).toJson())
      ..submit(code, tokens[active],
          version: 1, command: const EndActivation().toJson());

    final restored = newService(storage)..restore();
    final view = restored.view(code, tokens['enemigo']);
    expect(view['version'], 2);
    expect(view['activeSide'], isNot(active));
  });

  test('la API HTTP responde con JSON y códigos de error', () async {
    final handler = HttpApi(newService()).handler;
    Future<(int, Map<String, Object?>)> call(String method, String path,
        {Object? body, String? token}) async {
      final response = await handler(Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {if (token != null) 'authorization': 'Bearer $token'},
      ));
      return (
        response.statusCode,
        jsonDecode(await response.readAsString()) as Map<String, Object?>
      );
    }

    final (s1, created) = await call('POST', '/matches',
        body: {'map': 'vado', 'mission': 'defensa_vado', 'roster': roster});
    expect(s1, 200);
    final code = created['code']! as String;
    final (s2, _) = await call('GET', '/matches/$code', token: 'mal');
    expect(s2, 403);
    final (s3, joined) =
        await call('POST', '/matches/$code/join', body: {'roster': roster});
    expect(s3, 200);
    final guestToken = joined['token']! as String;
    final (s4, view) =
        await call('GET', '/matches/$code?since=0', token: guestToken);
    expect(s4, 200);
    expect(view['status'], 'despliegue');
    final (s6, deployed) = await call('POST', '/matches/$code/deployment',
        body: {'centers': {}}, token: guestToken);
    expect(s6, 200);
    expect(deployed['status'], 'despliegue');
    final (s5, error) = await call('POST', '/matches', body: {'roster': {}});
    expect(s5, 400);
    expect(error['error'], 'roster_squads');
  });
}
