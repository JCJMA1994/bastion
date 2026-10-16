import 'package:flutter/foundation.dart';
import 'package:rules_engine/rules_engine.dart' show BattleState, Side, Squad, Vec2;

/// Lo que necesita el tablero Flame de cualquier pantalla: estado que
/// dibujar, selección y toques. Lo implementan el despliegue y la batalla.
abstract class BoardController extends ChangeNotifier {
  BattleState get state;
  String? get selectedSquadId;
  String? get activeSquadId => null;

  /// Bando que controla este dispositivo (en multijugador puede ser el
  /// enemigo).
  Side get mySide => Side.jugador;

  /// Multiplicador de velocidad de animación (0 = sin animaciones). Lo fija
  /// la pantalla a partir de los ajustes y de la accesibilidad del sistema.
  double animationFactor = 1;

  /// Escuadras que no se dibujan (el despliegue del rival en multijugador).
  bool isHidden(Squad squad) => false;

  void select(String squadId);

  /// Toque en una zona vacía del tablero, en pulgadas.
  void tapBoard(Vec2 point) {}
}
