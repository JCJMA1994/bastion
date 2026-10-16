import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guarda la campaña y la batalla en curso en el dispositivo. La batalla se
/// guarda como configuración + comandos y se rejuega al cargarla.
class CampaignRepository {
  CampaignRepository(this._prefs);

  static Future<CampaignRepository> open() async =>
      CampaignRepository(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _campaignKey = 'bastion.campaign.v1';
  static const _battleKey = 'bastion.battle.v1';
  static const _tutorialKey = 'bastion.tutorial.done';

  bool get tutorialDone => _prefs.getBool(_tutorialKey) ?? false;
  Future<void> markTutorialDone() => _prefs.setBool(_tutorialKey, true);
  Future<void> resetTutorial() => _prefs.remove(_tutorialKey);

  Map<String, Object?>? loadCampaign() => _read(_campaignKey);
  Map<String, Object?>? loadBattle() => _read(_battleKey);

  Future<void> saveCampaign(Map<String, Object?> json) =>
      _prefs.setString(_campaignKey, jsonEncode(json));
  Future<void> saveBattle(Map<String, Object?> json) =>
      _prefs.setString(_battleKey, jsonEncode(json));

  Future<void> clearCampaign() => _prefs.remove(_campaignKey);
  Future<void> clearBattle() => _prefs.remove(_battleKey);

  Map<String, Object?>? _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, Object?>;
    } on FormatException {
      return null;
    }
  }
}
