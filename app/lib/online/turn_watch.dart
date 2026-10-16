import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rules_engine/rules_engine.dart' show Side;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'online_client.dart';

/// Avisa de las partidas online en las que te toca jugar.
abstract interface class TurnWatcher {
  /// Empieza a vigilar la partida de [ticket] en [serverUrl].
  Future<void> watch(String serverUrl, MatchTicket ticket);

  /// Deja de vigilar (al salir o terminar la partida).
  Future<void> stop();
}

/// Sin avisos (tests y plataformas sin segundo plano).
class NoopTurnWatcher implements TurnWatcher {
  const NoopTurnWatcher();
  @override
  Future<void> watch(String serverUrl, MatchTicket ticket) async {}
  @override
  Future<void> stop() async {}
}

/// Mensaje a mostrar, o nulo si no hay que avisar. Avisa una sola vez por
/// cada versión de la partida.
String? turnMessage(MatchView view, Side mySide, {int? lastNotifiedVersion}) {
  final key = view.version;
  if (lastNotifiedVersion == key) return null;
  if (view.deploying && !view.deployed.contains(mySide)) {
    return 'Tu rival se ha unido. Te toca desplegar.';
  }
  if (view.status == 'enCurso' && view.activeSide == mySide) {
    return 'Te toca. Tu compañía espera órdenes.';
  }
  if (view.status == 'terminada') return 'La batalla ha terminado.';
  return null;
}

/// Tarea periódica (WorkManager en Android, BGTaskScheduler en iOS) que
/// consulta el servidor y muestra una notificación local. No necesita
/// cuentas de push: el servidor solo se consulta, no envía nada.
class BackgroundTurnWatcher implements TurnWatcher {
  const BackgroundTurnWatcher();

  static const task = 'bastion.turnos';
  static const _matchKey = 'bastion.online.watch';
  static const _notifiedKey = 'bastion.online.notifiedVersion';

  /// Llamar una vez al arrancar la app.
  static Future<void> initialize() async {
    await Workmanager().initialize(turnWatchDispatcher);
    await _notifications().then((plugin) => plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission());
  }

  @override
  Future<void> watch(String serverUrl, MatchTicket ticket) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _matchKey,
        jsonEncode({
          'server': serverUrl,
          'code': ticket.code,
          'token': ticket.token,
          'side': ticket.side.name,
        }));
    await prefs.remove(_notifiedKey);
    await Workmanager().registerPeriodicTask(
      task,
      task,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  @override
  Future<void> stop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_matchKey);
    await Workmanager().cancelByUniqueName(task);
  }

  /// Ejecutado en segundo plano.
  static Future<void> check() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_matchKey);
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, Object?>;
    final ticket = MatchTicket(
      code: json['code']! as String,
      token: json['token']! as String,
      side: Side.values.byName(json['side']! as String),
    );
    final client = OnlineClient(json['server']! as String);
    try {
      final view = await client.view(ticket, since: 1 << 30);
      final message = turnMessage(view, ticket.side,
          lastNotifiedVersion: prefs.getInt(_notifiedKey));
      if (message == null) return;
      await prefs.setInt(_notifiedKey, view.version);
      final plugin = await _notifications();
      await plugin.show(
        id: ticket.code.hashCode & 0x7fffffff,
        title: 'Bastión · partida ${ticket.code}',
        body: message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'turnos',
            'Turnos multijugador',
            channelDescription: 'Avisa cuando te toca en una partida online.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      if (view.status == 'terminada') await const BackgroundTurnWatcher().stop();
    } finally {
      client.close();
    }
  }

  static Future<FlutterLocalNotificationsPlugin> _notifications() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    return plugin;
  }
}

/// Punto de entrada de la tarea en segundo plano.
@pragma('vm:entry-point')
void turnWatchDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await BackgroundTurnWatcher.check();
    } on Object {
      // Sin red o servidor caído: se reintenta en el siguiente ciclo.
    }
    return true;
  });
}
