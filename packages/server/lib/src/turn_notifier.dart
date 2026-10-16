import 'dart:convert';
import 'dart:io';

import 'package:rules_engine/rules_engine.dart' show Side;

/// Avisa a un jugador de que le toca. El servidor lo llama al empezar el
/// despliegue, al cambiar el turno y al terminar la partida.
abstract interface class TurnNotifier {
  void yourTurn(String code, Side side, {required String reason});
}

/// Envía un POST JSON `{code, side, reason}` a [url]. Sirve para conectar
/// cualquier servicio de push: por ejemplo, una función en la nube que
/// busque el token FCM/APNs del jugador y envíe la notificación.
final class WebhookTurnNotifier implements TurnNotifier {
  WebhookTurnNotifier(this.url, {HttpClient? client})
      : _client = client ?? HttpClient();

  final Uri url;
  final HttpClient _client;

  @override
  void yourTurn(String code, Side side, {required String reason}) {
    // Sin await: un aviso que falla nunca bloquea la partida.
    () async {
      try {
        final request = await _client.postUrl(url);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'code': code, 'side': side.name, 'reason': reason}));
        await (await request.close()).drain<void>();
      } on Object catch (e) {
        stderr.writeln('Aviso de turno no enviado ($code): $e');
      }
    }();
  }
}

/// Guarda los avisos en memoria, para tests.
final class RecordingTurnNotifier implements TurnNotifier {
  final List<(String, Side, String)> sent = [];

  @override
  void yourTurn(String code, Side side, {required String reason}) =>
      sent.add((code, side, reason));
}
