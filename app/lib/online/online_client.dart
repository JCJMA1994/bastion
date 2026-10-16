import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rules_engine/rules_engine.dart'
    show Command, OrderType, ProfileCatalog, Side, Vec2;

/// Error devuelto por el servidor, con su código ("not_your_turn", "full"…).
class OnlineError implements Exception {
  const OnlineError(this.status, this.code);
  final int status;
  final String code;

  @override
  String toString() => 'OnlineError($status, $code)';
}

class MatchTicket {
  const MatchTicket({required this.code, required this.token, required this.side});
  final String code;
  final String token;
  final Side side;
}

/// Compañía elegida para el multijugador.
class RosterDraft {
  const RosterDraft({required this.profileIds, required this.hand});

  /// Presupuesto de una compañía multijugador (debe coincidir con el servidor).
  static const budget = 150;
  static const maxSquads = 4;
  static const maxHand = 3;

  static const standard = RosterDraft(
    profileIds: ['capitana', 'lanceros', 'tiradores', 'granaderos'],
    hand: [OrderType.avanceForzado, OrderType.cuerpoATierra, OrderType.repetid],
  );

  final List<String> profileIds;
  final List<OrderType> hand;

  int cost(ProfileCatalog catalog) =>
      profileIds.fold(0, (sum, id) => sum + (catalog[id].cost ?? 0));

  bool isValid(ProfileCatalog catalog) =>
      profileIds.isNotEmpty &&
      profileIds.length <= maxSquads &&
      hand.length <= maxHand &&
      cost(catalog) <= budget &&
      profileIds.where((id) => catalog[id].unique).toSet().length ==
          profileIds.where((id) => catalog[id].unique).length;

  Map<String, Object?> toJson(ProfileCatalog catalog) => {
        'squads': [
          for (final id in profileIds)
            {'profile': id, 'soldiers': catalog[id].soldiers},
        ],
        'hand': [for (final o in hand) o.id],
      };
}

class MatchView {
  const MatchView({
    required this.status,
    required this.version,
    required this.commands,
    this.setup,
    this.deployed = const {},
    this.activeSide,
  });

  /// esperando, despliegue, enCurso o terminada.
  final String status;
  final int version;
  final List<Command> commands;

  /// Bandos que ya confirmaron el despliegue.
  final Set<Side> deployed;
  final Side? activeSide;

  /// Configuración; nula mientras se espera al rival. Durante el despliegue
  /// solo trae las posiciones propias.
  final Map<String, Object?>? setup;

  bool get deploying => status == 'despliegue';
  bool get started => status == 'enCurso' || status == 'terminada';
}

/// Cliente de la API del servidor de partidas.
class OnlineClient {
  OnlineClient(String baseUrl, {http.Client? client})
      : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = client ?? http.Client();

  final Uri _base;
  final http.Client _http;

  Future<MatchTicket> create(Map<String, Object?> roster,
          {String map = 'molino', String mission = 'dominio'}) =>
      _ticket(_post('matches', {'map': map, 'mission': mission, 'roster': roster}));

  Future<MatchTicket> join(String code, Map<String, Object?> roster) => _ticket(
      _post('matches/${code.trim().toUpperCase()}/join', {'roster': roster}));

  /// Confirma el despliegue: centro de cada escuadra propia.
  Future<void> deploy(MatchTicket ticket, Map<String, Vec2> centers) => _send(
      http.Request('POST', _base.resolve('matches/${ticket.code}/deployment'))
        ..headers['authorization'] = 'Bearer ${ticket.token}'
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'centers': {for (final e in centers.entries) e.key: e.value.toJson()},
        }));

  Future<MatchView> view(MatchTicket ticket, {int since = 0}) async {
    final json = await _send(http.Request(
        'GET', _base.resolve('matches/${ticket.code}?since=$since'))
      ..headers['authorization'] = 'Bearer ${ticket.token}');
    return MatchView(
      status: json['status']! as String,
      version: (json['version']! as num).toInt(),
      setup: json['setup'] as Map<String, Object?>?,
      deployed: {
        for (final s in (json['deployed'] as List<Object?>?) ?? const [])
          Side.values.byName(s! as String),
      },
      activeSide: json['activeSide'] == null
          ? null
          : Side.values.byName(json['activeSide']! as String),
      commands: [
        for (final c
            in (json['commands']! as List<Object?>).cast<Map<String, Object?>>())
          Command.fromJson(c),
      ],
    );
  }

  Future<void> submit(MatchTicket ticket, int version, Command command) => _send(
      http.Request('POST', _base.resolve('matches/${ticket.code}/commands'))
        ..headers['authorization'] = 'Bearer ${ticket.token}'
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({'version': version, 'command': command.toJson()}));

  Future<MatchTicket> _ticket(Future<Map<String, Object?>> response) async {
    final json = await response;
    return MatchTicket(
      code: json['code']! as String,
      token: json['token']! as String,
      side: Side.values.byName(json['side']! as String),
    );
  }

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body) =>
      _send(http.Request('POST', _base.resolve(path))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode(body));

  Future<Map<String, Object?>> _send(http.Request request) async {
    final streamed =
        await _http.send(request).timeout(const Duration(seconds: 10));
    final response = await http.Response.fromStream(streamed);
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    if (response.statusCode != 200) {
      throw OnlineError(response.statusCode, (json['error'] as String?) ?? 'http');
    }
    return json;
  }

  void close() => _http.close();
}
