import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import '../art/renderers.dart';
import '../theme/bastion_tokens.dart';
import 'battle_controller.dart';
import 'board_controller.dart';
import 'components/board_component.dart';
import 'components/effects_component.dart';
import 'components/preview_component.dart';
import 'components/squad_component.dart';

/// Juego Flame: solo dibuja el estado y traduce toques en llamadas al
/// controlador. Las reglas viven en `rules_engine`.
class BastionGame extends FlameGame {
  BastionGame({required this.controller, this.renderers = const Renderers.vector()})
      : super(
          camera: CameraComponent.withFixedResolution(
            width: 44 * pixelsPerInch,
            height: 28 * pixelsPerInch,
          ),
        );

  /// Escala del mundo: 1 pulgada de juego = 20 unidades.
  static const double pixelsPerInch = 20;

  static const double minZoom = 1;
  static const double maxZoom = 3;

  /// Tamaño del tablero en unidades del mundo.
  static final Vector2 boardSize = Vector2(44, 28) * pixelsPerInch;

  final BoardController controller;

  /// Cómo se dibujan tropas, terreno y efectos (vectores o sprites).
  final Renderers renderers;

  /// Hay un pellizco en curso: el arrastre sobre el tablero no desplaza.
  bool pinching = false;

  double get zoom => camera.viewfinder.zoom;

  /// Zona visible del tablero en unidades del mundo.
  Vector2 get visibleSize => boardSize / zoom;

  /// Centro de lo que se ve ahora.
  Vector2 get viewCenter => camera.viewfinder.position + visibleSize / 2;

  /// Cambia el zoom manteniendo [focus] (en el mundo) en el mismo sitio de
  /// la pantalla. Sin [focus], acerca o aleja desde el centro de la vista.
  void setZoom(double value, {Vector2? focus}) {
    final target = value.clamp(minZoom, maxZoom).toDouble();
    final point = focus ?? viewCenter;
    final offsetOnScreen = (point - camera.viewfinder.position) * zoom;
    camera.viewfinder.zoom = target;
    camera.viewfinder.position = point - offsetOnScreen / target;
    _clampView();
  }

  void zoomBy(double factor, {Vector2? focus}) =>
      setZoom(zoom * factor, focus: focus);

  /// Desplaza la vista; [canvasDelta] en píxeles de pantalla.
  void panByCanvas(Vector2 canvasDelta) {
    final scale = _canvasScale * zoom;
    if (scale <= 0) return;
    camera.viewfinder.position -= canvasDelta / scale;
    _clampView();
  }

  void resetView() {
    camera.viewfinder
      ..zoom = 1
      ..position = Vector2.zero();
  }

  /// Escala de la resolución fija a la pantalla real (con bandas si la
  /// proporción no coincide).
  double get _canvasScale {
    if (canvasSize.x == 0 || canvasSize.y == 0) return 1;
    final sx = canvasSize.x / boardSize.x;
    final sy = canvasSize.y / boardSize.y;
    return sx < sy ? sx : sy;
  }

  void _clampView() {
    final visible = visibleSize;
    final p = camera.viewfinder.position;
    camera.viewfinder.position = Vector2(
      p.x.clamp(0, (boardSize.x - visible.x).clamp(0, double.infinity)).toDouble(),
      p.y.clamp(0, (boardSize.y - visible.y).clamp(0, double.infinity)).toDouble(),
    );
  }

  @override
  Color backgroundColor() => BastionColors.mesa900;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    await world.add(BoardComponent(controller));
    for (final squad in controller.state.squads) {
      await world.add(SquadComponent(squad: squad, controller: controller));
    }
    final c = controller;
    if (c is BattleController) {
      await world.add(PreviewComponent(c));
      await world.add(EffectsComponent(c));
    }
  }
}
