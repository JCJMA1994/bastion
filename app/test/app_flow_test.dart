import 'dart:math' as math;

import 'package:bastion/app/app_controller.dart';
import 'package:bastion/data/campaign_repository.dart';
import 'package:bastion/data/game_data.dart';
import 'package:bastion/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_engine/rules_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppController> _app() async => AppController(
      await GameData.load(),
      await CampaignRepository.open(),
      await SettingsController.open(),
      random: math.Random(4),
    );

/// El jugador activa y termina sus escuadras sin hacer nada más.
void _passPlayerTurns(AppController app) {
  final battle = app.battle!;
  var guard = 0;
  while (battle.state.step != BattleStep.terminada && guard++ < 200) {
    final squad = battle.state
        .aliveSquadsOf(Side.jugador)
        .firstWhere((s) => !s.activatedThisRound);
    battle
      ..select(squad.id)
      ..activateSelected()
      ..endActivation();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bucle completo: campaña, despliegue, batalla y resultado', () async {
    final app = await _app();
    app.newCampaign();
    expect(app.screen, AppScreen.campana);

    app.travel('n0');
    expect(app.screen, AppScreen.compania);

    app.startDeployment(app.run!.squads.map((s) => s.id).take(4).toList());
    expect(app.screen, AppScreen.despliegue);
    expect(app.deployment!.isValid, isTrue);

    app.beginBattle();
    expect(app.screen, AppScreen.batalla);
    _passPlayerTurns(app);

    app.finishBattle();
    expect(app.screen, AppScreen.resultado);
    expect(app.report, isNotNull);
    expect(app.run!.completed, contains('n0'));
  });

  test('una batalla a medias se recupera al reabrir la app', () async {
    final first = await _app();
    first
      ..newCampaign()
      ..travel('n0');
    first.startDeployment(first.run!.squads.map((s) => s.id).take(2).toList());
    first.beginBattle();
    final battle = first.battle!;
    final squad = battle.state
        .aliveSquadsOf(Side.jugador)
        .firstWhere((s) => !s.activatedThisRound);
    battle
      ..select(squad.id)
      ..activateSelected()
      ..endActivation();
    final round = battle.state.round;
    await Future<void>.delayed(Duration.zero);

    final reopened = await _app();
    reopened.restore();
    expect(reopened.screen, AppScreen.batalla);
    expect(reopened.quickBattle, isFalse);
    expect(reopened.battle!.state.round, round);
    expect(
        reopened.battle!.state.squadById(squad.id).activatedThisRound ||
            reopened.battle!.state.round > 1,
        isTrue);
  });
}
