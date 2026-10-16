import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:rules_engine/rules_engine.dart'
    show Encounter, MapTemplate, ProfileCatalog;

import '../art/decor.dart';

/// Datos del juego cargados desde `assets/data/` (copia de `data/`).
class GameData {
  const GameData({
    required this.catalog,
    required this.maps,
    required this.encounters,
    this.decor = const {},
  });

  final ProfileCatalog catalog;
  final Map<String, MapTemplate> maps;
  final Map<String, Encounter> encounters;

  /// Decoración fijada a mano en `maps.json`, por id de área (solo visual).
  final Map<String, List<DecorItem>> decor;

  static Future<GameData> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    Future<Map<String, Object?>> read(String file) async =>
        jsonDecode(await assets.loadString('assets/data/$file'))
            as Map<String, Object?>;
    final maps = await read('maps.json');
    return GameData(
      catalog: ProfileCatalog.fromJson(await read('units.json')),
      maps: MapTemplate.catalogFromJson(maps),
      encounters: Encounter.catalogFromJson(await read('encounters.json')),
      decor: DecorPlanner.explicitFromMaps(maps),
    );
  }
}
