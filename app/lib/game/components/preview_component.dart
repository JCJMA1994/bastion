import 'dart:ui';

import 'package:flame/components.dart';

import '../../theme/bastion_tokens.dart';
import '../bastion_game.dart';
import '../battle_controller.dart';

/// Capa de previsualización: alcance de movimiento, formación fantasma al
/// arrastrar y línea de tiro hacia el enemigo seleccionado.
class PreviewComponent extends Component {
  PreviewComponent(this.controller) : super(priority: 10);

  final BattleController controller;

  static const double _ppi = BastionGame.pixelsPerInch;

  final _label = TextPaint(
    style: BastionText.cifra()
        .copyWith(fontSize: 13, color: BastionColors.latonClaro),
  );

  @override
  void render(Canvas canvas) {
    final active = controller.active;
    if (active == null || !controller.isPlayerTurn) return;
    final origin = active.centroid;
    final o = Offset(origin.x * _ppi, origin.y * _ppi);

    if (controller.canMoveActive) {
      canvas.drawCircle(
          o,
          controller.moveAllowance * _ppi,
          Paint()
            ..color = BastionColors.laton.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    final ghost = controller.ghost;
    if (ghost != null) {
      for (final soldier in active.alive) {
        final dest = ghost[soldier.id];
        if (dest == null) continue;
        final tooFar =
            soldier.position.distanceTo(dest) > controller.moveAllowance;
        canvas.drawCircle(
            Offset(dest.x * _ppi, dest.y * _ppi),
            soldier.baseRadius * _ppi,
            Paint()
              ..color = (tooFar ? BastionColors.peligro : BastionColors.laton)
                  .withValues(alpha: 0.45));
      }
    }

    final target = controller.enemyTarget;
    if (target != null) {
      final lof = controller.field.lineOfFire(active, target);
      final t = target.centroid;
      final end = Offset(t.x * _ppi, t.y * _ppi);
      canvas.drawLine(
          o,
          end,
          Paint()
            ..color = lof.visible ? BastionColors.laton : BastionColors.peligro
            ..strokeWidth = 2);
      final text = !lof.visible
          ? 'Sin visión'
          : '${lof.distance.toStringAsFixed(0)}"${lof.cover ? ' · cobertura' : ''}';
      final mid = Vector2((o.dx + end.dx) / 2, (o.dy + end.dy) / 2 - 14);
      final box = Rect.fromCenter(
          center: Offset(mid.x, mid.y), width: text.length * 8.0 + 12, height: 20);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = BastionColors.mesa900);
      _label.render(canvas, text, mid, anchor: Anchor.center);
    }
  }
}
