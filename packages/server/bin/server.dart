// Servidor de partidas de Bastión.
//
//   dart run bin/server.dart [--port 8080] [--data ../../data] [--store partidas]
//                            [--config config] [--telemetry telemetria]
//
// BASTION_ADMIN_TOKEN activa el panel /admin y sus endpoints.
//
// Con BASTION_WEBHOOK=https://… avisa de cada cambio de turno con un POST
// JSON {code, side, reason} (por ejemplo, a una función que envíe el push).
import 'dart:convert';
import 'dart:io';

import 'package:bastion_server/bastion_server.dart';
import 'package:rules_engine/rules_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final port = int.parse(option('port', Platform.environment['PORT'] ?? '8080'));
  final dataDir = option('data', '../../data');
  Map<String, Object?> read(String file) =>
      jsonDecode(File('$dataDir/$file').readAsStringSync())
          as Map<String, Object?>;

  final service = MatchService(
    catalog: ProfileCatalog.fromJson(read('units.json')),
    maps: MapTemplate.catalogFromJson(read('maps.json')),
    storage: FileMatchStorage(Directory(option('store', 'partidas'))),
    notifier: Platform.environment['BASTION_WEBHOOK'] == null
        ? null
        : WebhookTurnNotifier(Uri.parse(Platform.environment['BASTION_WEBHOOK']!)),
  )..restore();

  final telemetry =
      TelemetryStore(directory: Directory(option('telemetry', 'telemetria')))
        ..restore();
  final adminToken = Platform.environment['BASTION_ADMIN_TOKEN'];
  if (adminToken == null || adminToken.length < 16) {
    stdout.writeln('Aviso: sin BASTION_ADMIN_TOKEN (16+ caracteres) el panel '
        '/admin no está disponible.');
  }
  final api = HttpApi(
    service,
    telemetry: telemetry,
    config: RemoteConfigStore(Directory(option('config', 'config'))),
    adminToken: (adminToken?.length ?? 0) >= 16 ? adminToken : null,
  );
  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(api.handler);
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Bastión escuchando en http://${server.address.host}:${server.port} '
      '(${service.matchCount} partidas recuperadas)');
}
