import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:rules_engine/rules_engine.dart' show Objective, Vec2;

import '../../theme/bastion_tokens.dart';
import '../bastion_game.dart';
import '../board_controller.dart';

/// Tablero: campo, cuadrícula de 1", zonas de despliegue, terreno,
/// parapetos y objetivos. Los toques en zonas vacías van a
/// [BoardController.tapBoard].
class BoardComponent extends PositionComponent
    with TapCallbacks, DragCallbacks, HasGameReference<BastionGame> {
  BoardComponent(this.controller)
      : super(
          size: Vector2(controller.state.board.width,
                  controller.state.board.height) *
              BastionGame.pixelsPerInch,
        );

  final BoardController controller;

  static const double _ppi = BastionGame.pixelsPerInch;

  Offset _p(Vec2 v) => Offset(v.x * _ppi, v.y * _ppi);

  @override
  void onTapDown(TapDownEvent event) => controller.tapBoard(
      Vec2(event.localPosition.x / _ppi, event.localPosition.y / _ppi));

  /// Arrastrar sobre una zona vacía desplaza la vista (si hay zoom).
  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (game.pinching) return;
    game.panByCanvas(event.canvasDelta);
  }

  /// Suelo, cuadrícula, zonas, terreno y objetivos no cambian entre
  /// fotogramas: se pintan una vez y se reutilizan. Solo se rehacen si se
  /// añade un parapeto (Fortificar).
  Picture? _static;
  int _staticKey = -1;

  @override
  void render(Canvas canvas) {
    final key = controller.state.fortifications.length;
    if (_static == null || key != _staticKey) {
      final recorder = PictureRecorder();
      _paintStatic(Canvas(recorder));
      _static?.dispose();
      _static = recorder.endRecording();
      _staticKey = key;
    }
    canvas.drawPicture(_static!);
  }

  @override
  void onRemove() {
    _static?.dispose();
    _static = null;
    super.onRemove();
  }

  void _paintStatic(Canvas canvas) {
    final state = controller.state;
    final board = state.board;
    final terrain = game.renderers.terrain;
    terrain.drawGround(canvas, Size(size.x, size.y));

    final grid = Paint()
      ..color = BastionColors.tinta.withValues(alpha: terrain.gridAlpha)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= board.width; x++) {
      canvas.drawLine(Offset(x * _ppi, 0), Offset(x * _ppi, size.y), grid);
    }
    for (var y = 0.0; y <= board.height; y++) {
      canvas.drawLine(Offset(0, y * _ppi), Offset(size.x, y * _ppi), grid);
    }

    final zones = state.mission.deploymentZones(board.width, board.height);
    zones.forEach((side, zone) {
      final color =
          side == controller.mySide ? BastionColors.laton : BastionColors.cobalto;
      canvas.drawRect(
          Rect.fromLTWH(zone.x * _ppi, zone.y * _ppi, zone.width * _ppi,
              zone.height * _ppi),
          Paint()..color = color.withValues(alpha: 0.08));
    });

    for (final area in [...board.terrain, ...state.fortifications]) {
      terrain.drawArea(canvas,
          area, Path()..addPolygon(area.polygon.points.map(_p).toList(), true));
    }

    for (final objective in board.objectives) {
      terrain.drawObjective(
          canvas, _p(objective.position), Objective.radius * _ppi + 4,
          central: objective.value > 1);
    }
  }
}
