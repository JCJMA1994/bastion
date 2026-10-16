import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

ProfileCatalog loadCatalog() => ProfileCatalog.fromJson(
    jsonDecode(File('../../data/units.json').readAsStringSync())
        as Map<String, Object?>);

List<Vec2> column(double x, double y, int n) =>
    [for (var i = 0; i < n; i++) Vec2(x, y + i * 1.5)];

/// Juega una batalla completa con una IA trivial: activa la primera escuadra
/// disponible y dispara al primer enemigo que pueda; si no, termina.
List<String> playOut(int seed, ProfileCatalog catalog) {
  final lanceros = catalog['lanceros'];
  final tiradores = catalog['tiradores'];
  final state = BattleState(
    board: const Board(objectives: [
      Objective(id: 'centro', position: Vec2(22, 14), value: 2),
    ]),
    squads: [
      Squad.deploy(
          id: 'J1', side: Side.jugador, profile: lanceros, positions: column(10, 4, 5)),
      Squad.deploy(
          id: 'J2', side: Side.jugador, profile: tiradores, positions: column(10, 16, 5)),
      Squad.deploy(
          id: 'E1', side: Side.enemigo, profile: lanceros, positions: column(30, 4, 5)),
      Squad.deploy(
          id: 'E2', side: Side.enemigo, profile: tiradores, positions: column(30, 16, 5)),
    ],
  );
  final engine = BattleEngine(state: state, dice: SeededDice(seed));
  final log = <String>[];
  void record(List<GameEvent> events) =>
      log.addAll(events.map((e) => jsonEncode(e.toJson())));

  record(engine.start());
  var guard = 0;
  while (state.step != BattleStep.terminada && guard++ < 500) {
    final side = state.activeSide!;
    final squad =
        state.aliveSquadsOf(side).firstWhere((s) => !s.activatedThisRound);
    record(engine.apply(ActivateSquad(squad.id)));
    final weapon = squad.profile.weapons.firstWhere((w) => !w.isMelee);
    final target = state.aliveSquadsOf(side.opponent).where((t) =>
        engine.field.isVisible(squad, t) &&
        engine.field.distance(squad, t) <= weapon.range);
    if (target.isEmpty) {
      record(engine.apply(const EndActivation()));
    } else {
      record(engine.apply(
          Shoot(weaponId: weapon.id, targetSquadId: target.first.id)));
    }
  }
  return log;
}

void main() {
  test('el catálogo carga los 8 perfiles', () {
    final catalog = loadCatalog();
    expect(catalog.all, hasLength(8));
    expect(catalog['canon'].weapons.single.mode, HitMode.dispersion);
    expect(catalog['zapadores'].weapons.single.mode, HitMode.automatico);
    expect(catalog['tiradores'].meleeWeapon, same(Weapon.improvised));
  });

  test('la misma semilla y los mismos comandos reproducen la batalla', () {
    final catalog = loadCatalog();
    final a = playOut(42, catalog);
    final b = playOut(42, catalog);
    expect(a, isNotEmpty);
    expect(a, b);
    expect(a.last, contains('battle_ended'));
  });
}
