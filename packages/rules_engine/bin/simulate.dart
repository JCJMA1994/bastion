// Simulador de balance de Bastión.
//
//   dart run bin/simulate.dart duelos [--batallas 100] [--json salida.json]
//   dart run bin/simulate.dart campana [--campanas 50]
//   dart run bin/simulate.dart ordenes [--batallas 100]
//
// Ejecutar desde packages/rules_engine. Lee los datos de ../../data.
import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart';

void main(List<String> args) {
  final mode = args.isEmpty ? 'duelos' : args.first;
  int option(String name, int fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length
        ? int.tryParse(args[i + 1]) ?? fallback
        : fallback;
  }

  Map<String, Object?> read(String file) =>
      jsonDecode(File('../../data/$file').readAsStringSync())
          as Map<String, Object?>;
  final catalog = ProfileCatalog.fromJson(read('units.json'));
  final maps = MapTemplate.catalogFromJson(read('maps.json'));
  final encounters = Encounter.catalogFromJson(read('encounters.json'));
  final simulator =
      Simulator(catalog: catalog, maps: maps, encounters: encounters);

  final watch = Stopwatch()..start();
  switch (mode) {
    case 'duelos':
      _duels(simulator, catalog, option('batallas', 100), args);
    case 'campana':
      _campaigns(simulator, option('campanas', 50));
    case 'ordenes':
      _ordersImpact(catalog, maps, encounters, option('batallas', 100));
    default:
      stderr.writeln('Modo desconocido: $mode (duelos, campana, ordenes)');
      exitCode = 64;
      return;
  }
  stdout.writeln('\nTiempo: ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
}

String _pct(double v) => '${(v * 100).round()}%'.padLeft(5);

void _duels(Simulator sim, ProfileCatalog catalog, int battles, List<String> args) {
  final ids = [
    for (final p in catalog.all)
      if (!p.unique) p.id,
  ];
  final results = sim.roundRobin(ids, battles: battles);

  stdout.writeln('Duelos: 2 contra 2, $battles batallas por pareja.\n');
  stdout.writeln('Fila contra columna: % de victorias de la fila.\n');
  const width = 13;
  stdout.writeln(''.padRight(width) + ids.map((i) => i.padLeft(width)).join());
  for (final row in ids) {
    final cells = StringBuffer(row.padRight(width));
    for (final col in ids) {
      if (row == col) {
        cells.write('—'.padLeft(width));
        continue;
      }
      final d = results.firstWhere((r) =>
          (r.a == row && r.b == col) || (r.a == col && r.b == row));
      final rate = d.a == row ? d.winRateA : d.winRateB;
      cells.write(_pct(rate).padLeft(width));
    }
    stdout.writeln(cells);
  }

  stdout.writeln('\nResumen por perfil (media contra todos):\n');
  stdout.writeln('${'perfil'.padRight(width)}${'victorias'.padLeft(11)}'
      '${'coste'.padLeft(8)}${'vict./coste'.padLeft(13)}');
  final summary = <(String, double, int)>[];
  for (final id in ids) {
    var sum = 0.0;
    var n = 0;
    for (final d in results) {
      if (d.a == id) {
        sum += d.winRateA;
        n++;
      } else if (d.b == id) {
        sum += d.winRateB;
        n++;
      }
    }
    summary.add((id, n == 0 ? 0.0 : sum / n, catalog[id].cost ?? 0));
  }
  summary.sort((x, y) => y.$2.compareTo(x.$2));
  final jsonIndex = args.indexOf('--json');
  if (jsonIndex >= 0 && jsonIndex + 1 < args.length) {
    File(args[jsonIndex + 1]).writeAsStringSync(jsonEncode({
      'batallas': battles,
      'perfiles': {
        for (final (id, rate, cost) in summary) id: {'victorias': rate, 'coste': cost},
      },
    }));
  }
  for (final (id, rate, cost) in summary) {
    final value = cost == 0 ? 0 : rate * 100 / cost;
    stdout.writeln('${id.padRight(width)}${_pct(rate).padLeft(11)}'
        '${'$cost'.padLeft(8)}${value.toStringAsFixed(2).padLeft(13)}');
  }
  stdout.writeln('\nUn perfil equilibrado ronda el 50%. "vict./coste" alto '
      'indica que está barato para lo que rinde.');
}

void _campaigns(Simulator sim, int runs) {
  final s = sim.campaigns(runs: runs);
  stdout
    ..writeln('Campañas jugadas por la IA: ${s.runs}\n')
    ..writeln('Victorias:            ${_pct(s.victoryRate)}')
    ..writeln('Derrotas:             ${s.defeats}')
    ..writeln('Sin terminar:         ${s.unfinished}')
    ..writeln('Batallas ganadas:     ${_pct(s.battleWinRate)} de ${s.battles}')
    ..writeln('Escuadras caídas:     ${(s.fallen / s.runs).toStringAsFixed(1)} por campaña')
    ..writeln('Días de media:        ${s.averageDays.toStringAsFixed(1)}');
  if (s.defeatsByNode.isNotEmpty) {
    stdout.writeln('\nDerrotas por nodo: ${s.defeatsByNode}');
  }
  stdout.writeln('\nObjetivo de diseño orientativo: 35–55% de victorias con '
      'la IA (un jugador humano debería superarla).');
}

void _ordersImpact(ProfileCatalog catalog, Map<String, MapTemplate> maps,
    Map<String, Encounter> encounters, int battles) {
  final withOrders = Simulator(catalog: catalog, maps: maps, encounters: encounters);
  final without = Simulator(
      catalog: catalog,
      maps: maps,
      encounters: encounters,
      ai: const SimpleAi(useOrders: false));
  final a = withOrders.campaigns(runs: battles);
  final b = without.campaigns(runs: battles);
  stdout
    ..writeln('Efecto de las órdenes en $battles campañas:\n')
    ..writeln('Con órdenes:  ${_pct(a.victoryRate)} victorias, '
        '${_pct(a.battleWinRate)} batallas ganadas')
    ..writeln('Sin órdenes:  ${_pct(b.victoryRate)} victorias, '
        '${_pct(b.battleWinRate)} batallas ganadas');
}
