import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_controller.dart';
import 'art/art_set.dart';
import 'core/env.dart';
import 'data/battle_stats.dart';
import 'data/campaign_repository.dart';
import 'data/game_data.dart';
import 'online/turn_watch.dart';
import 'remote_config/remote_config.dart';
import 'screens/logs_screen.dart';
import 'screens/battle_screen.dart';
import 'screens/campaign_screen.dart';
import 'screens/company_screen.dart';
import 'screens/deployment_screen.dart';
import 'screens/encounter_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/online_screen.dart';
import 'screens/results_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/supplies_screen.dart';
import 'settings/settings_controller.dart';
import 'settings/sounds.dart';
import 'telemetry/http_sink.dart';
import 'telemetry/telemetry.dart';
import 'theme/bastion_tokens.dart';

/// Mantiene vivo el listener del ciclo de vida de la app.
AppLifecycleListener? appLifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logs = MemorySink();
  Telemetry.instance = Telemetry(local: logs, minLevel: LogLevel.debug);

  // Errores no controlados: de Flutter y del resto de la app.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Telemetry.instance.error(details.exception, details.stack,
        name: 'FlutterError', data: {'library': details.library ?? ''});
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Telemetry.instance.error(error, stack, name: 'PlatformError');
    return true;
  };

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final settings = await SettingsController.open();
  Sounds.init(settings);

  // Configuración remota: valores por defecto + caché; se refresca en
  // segundo plano sin bloquear el arranque.
  final config = await RemoteConfig.load();
  final sink = HttpTelemetrySink(
    prefs: await SharedPreferences.getInstance(),
    serverUrl: settings.serverUrl,
    env: Env.name,
    appVersion: Env.appVersion,
  )..start(config.telemetryFlushInterval);
  final telemetry = Telemetry(
    local: logs,
    remote: Env.telemetryEnabled ? sink : null,
    minLevel: Env.isProd ? config.logLevel : LogLevel.debug,
    diagnosticsConsent: settings.diagnosticsConsent,
    analyticsConsent: settings.analyticsConsent,
  );
  Telemetry.instance = telemetry;
  settings.addListener(() {
    final hadConsent = telemetry.diagnosticsConsent || telemetry.analyticsConsent;
    telemetry
      ..diagnosticsConsent = settings.diagnosticsConsent
      ..analyticsConsent = settings.analyticsConsent;
    sink.serverUrl = settings.serverUrl;
    // Al retirar el consentimiento no se envía lo que quedaba en cola.
    if (hadConsent && !settings.diagnosticsConsent && !settings.analyticsConsent) {
      sink.discard();
    }
  });
  config.addListener(() {
    if (Env.isProd) telemetry.minLevel = config.logLevel;
    sink.start(config.telemetryFlushInterval);
  });
  unawaited(config.refresh(settings.serverUrl));
  appLifecycle = AppLifecycleListener(
    onPause: () => unawaited(telemetry.flush()),
    onResume: () => unawaited(config.refresh(settings.serverUrl)),
  );
  telemetry
    ..event('app_open', {'env': Env.name, 'version': Env.appVersion})
    ..info('app', 'Arranque', data: {'env': Env.name, 'version': Env.appVersion});
  TurnWatcher watcher = const NoopTurnWatcher();
  try {
    await BackgroundTurnWatcher.initialize();
    watcher = const BackgroundTurnWatcher();
  } on Object catch (e) {
    // Plataforma sin tareas en segundo plano: sin avisos, el resto funciona.
    debugPrint('Avisos de turno no disponibles: $e');
  }
  final app = AppController(
    await GameData.load(),
    await CampaignRepository.open(),
    settings,
    turnWatcher: watcher,
    stats: await BattleStats.open(),
    remoteConfig: config,
    logs: logs,
    art: await ArtSet.load(
        devicePixelRatio:
            PlatformDispatcher.instance.views.firstOrNull?.devicePixelRatio ?? 2),
  )..restore();
  runApp(BastionApp(app: app));
}

class BastionApp extends StatelessWidget {
  const BastionApp({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bastión',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: BastionColors.mesa900,
        colorScheme: const ColorScheme.dark(
          primary: BastionColors.laton,
          onPrimary: BastionColors.latonTinta,
          surface: BastionColors.mesa700,
          onSurface: BastionColors.tinta,
          error: BastionColors.peligro,
        ),
      ),
      // Respeta el tamaño de texto del sistema, con un tope para que el
      // tablero y los paneles sigan cabiendo en horizontal.
      builder: (context, child) => ListenableBuilder(
        listenable: Listenable.merge([
          app.settings,
          if (app.remoteConfig != null) app.remoteConfig!,
        ]),
        builder: (context, _) {
          final media = MediaQuery.of(context);
          final max = app.settings.largeText ? 1.35 : 1.15;
          final base = app.settings.largeText ? 1.2 : 1.0;
          final scale = (media.textScaler.scale(1) * base).clamp(1.0, max);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          );
        },
      ),
      home: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) => _screen(),
          ),
        ),
      ),
    );
  }

  Widget _screen() => switch (app.screen) {
        AppScreen.menu => MenuScreen(app: app),
        AppScreen.campana =>
          CampaignScreen(key: ValueKey('campana-${app.run?.day}'), app: app),
        AppScreen.compania => CompanyScreen(
            key: ValueKey('compania-${app.run?.currentNodeId}'), app: app),
        AppScreen.despliegue =>
          DeploymentScreen(key: ObjectKey(app.deployment), app: app),
        AppScreen.batalla => BattleScreen(
            key: ObjectKey(app.battle),
            controller: app.battle!,
            title: app.battleTitle,
            onFinished: app.finishBattle,
            settings: app.settings,
            renderers: app.renderers,
            showTutorial: app.showTutorial && !app.isOnlineBattle,
            onSkipTutorial: app.finishTutorial,
            onOpenSettings: app.openSettings,
          ),
        AppScreen.resultado => ResultsScreen(app: app),
        AppScreen.encuentro => EncounterScreen(app: app),
        AppScreen.suministros => SuppliesScreen(app: app),
        AppScreen.ajustes => SettingsScreen(
            settings: app.settings,
            stats: app.stats,
            onOpenLogs: app.logs == null ? null : app.openLogs,
            onBack: app.closeSettings,
            onReplayTutorial: app.replayTutorial,
          ),
        AppScreen.online => OnlineScreen(app: app),
        AppScreen.registro => LogsScreen(sink: app.logs!, onBack: app.closeLogs),
      };
}
