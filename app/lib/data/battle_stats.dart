import 'dart:convert';

import 'package:rules_engine/rules_engine.dart'
    show BattleState, BattleStep, Side;
import 'package:shared_preferences/shared_preferences.dart';

/// Resultados por perfil de las partidas reales del jugador, para contrastar
/// el balance del simulador con cómo se juega de verdad.
class ProfileRecord {
  ProfileRecord({this.battles = 0, this.wins = 0, this.survival = 0});

  factory ProfileRecord.fromJson(Map<String, Object?> json) => ProfileRecord(
        battles: (json['b']! as num).toInt(),
        wins: (json['w']! as num).toInt(),
        survival: (json['s']! as num).toDouble(),
      );

  int battles;
  int wins;

  /// Suma de la fracción de soldados que sobrevivieron.
  double survival;

  double get winRate => battles == 0 ? 0 : wins / battles;
  double get averageSurvival => battles == 0 ? 0 : survival / battles;

  Map<String, Object?> toJson() => {'b': battles, 'w': wins, 's': survival};
}

class BattleStats {
  BattleStats(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      for (final e in json.entries) {
        records[e.key] = ProfileRecord.fromJson(e.value! as Map<String, Object?>);
      }
    } on FormatException {
      // Datos dañados: se empieza de cero.
    }
  }

  static Future<BattleStats> open() async =>
      BattleStats(await SharedPreferences.getInstance());

  static const _key = 'bastion.stats.v1';

  final SharedPreferences _prefs;
  final Map<String, ProfileRecord> records = {};

  int get totalBattles =>
      records.values.fold(0, (sum, r) => sum + r.battles);

  /// Registra una batalla terminada desde el punto de vista de [side].
  void record(BattleState state, Side side) {
    if (state.step != BattleStep.terminada) return;
    for (final squad in state.squads.where((s) => s.side == side)) {
      final r = records.putIfAbsent(squad.profile.id, ProfileRecord.new);
      r
        ..battles += 1
        ..wins += state.winner == side ? 1 : 0
        ..survival += squad.aliveCount / squad.startingCount;
    }
    _prefs.setString(_key, export());
  }

  String export() =>
      jsonEncode({for (final e in records.entries) e.key: e.value.toJson()});

  void clear() {
    records.clear();
    _prefs.remove(_key);
  }
}
