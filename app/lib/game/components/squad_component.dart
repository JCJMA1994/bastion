import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:rules_engine/rules_engine.dart' show AttackResolved, Squad, Vec2;

import '../../art/renderers.dart';
import '../../theme/bastion_tokens.dart';
import '../bastion_game.dart';
import '../battle_controller.dart';
import '../board_controller.dart';

/// Dibuja los soldados de una escuadra: círculos latón para el jugador y
/// rombos cobalto para el enemigo. Tocar selecciona; arrastrar la escuadra
/// activa propone un movimiento.
///
/// Las posiciones dibujadas siguen a las reales con una animación, y los
/// soldados que caen se desvanecen en lugar de desaparecer de golpe.
class SquadComponent extends PositionComponent
    with TapCallbacks, DragCallbacks, HasGameReference<BastionGame> {
  SquadComponent({required this.squad, required this.controller})
      : super(size: Vector2(44, 28) * BastionGame.pixelsPerInch) {
    for (final s in squad.soldiers) {
      if (s.alive) _shown[s.id] = s.position;
    }
  }

  final Squad squad;
  final BoardController controller;

  static const double _ppi = BastionGame.pixelsPerInch;

  /// Margen extra para que el objetivo táctil se acerque a 44px.
  static const double _touchSlop = 0.6;

  /// Velocidad de la animación de movimiento, en pulgadas por segundo.
  static const double _speed = 16;

  /// Duración del desvanecimiento de una baja, en segundos.
  static const double _fadeTime = 0.8;

  /// Posición dibujada de cada soldado vivo.
  final Map<String, Vec2> _shown = {};

  /// Soldados caídos que aún se desvanecen: posición y tiempo restante.
  final Map<String, (Vec2, double)> _fading = {};

  Vector2 _drag = Vector2.zero();

  /// Hacia dónde miran los soldados: la escuadra enemiga más cercana.
  double _facing = 0;

  /// Segundos que le quedan a la pose de disparo.
  double _firingLeft = 0;
  int _seenFeed = -1;

  bool get _draggable {
    final c = controller;
    return c is BattleController &&
        c.state.activeSquadId == squad.id &&
        c.canMoveActive;
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      !controller.isHidden(squad) &&
      squad.alive.any((s) {
        final dx = point.x / _ppi - s.position.x;
        final dy = point.y / _ppi - s.position.y;
        final r = s.baseRadius + _touchSlop;
        return dx * dx + dy * dy <= r * r;
      });

  @override
  void onTapDown(TapDownEvent event) => controller.select(squad.id);

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _drag = Vector2.zero();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    final c = controller;
    if (!_draggable || c is! BattleController) return;
    _drag += event.localDelta;
    c.dragActive(Vec2(_drag.x / _ppi, _drag.y / _ppi));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final c = controller;
    if (_draggable && c is BattleController) c.dropActive();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _updateFacing();
    _updateFiring(dt);
    final factor = controller.animationFactor;
    // Sin animaciones: todo salta a su sitio y las bajas desaparecen ya.
    final step = factor == 0 ? double.infinity : _speed * factor * dt;
    if (factor == 0) _fading.clear();
    for (final s in squad.soldiers) {
      final shown = _shown[s.id];
      if (!s.alive) {
        if (shown != null) {
          if (factor > 0) _fading[s.id] = (shown, _fadeTime);
          _shown.remove(s.id);
        }
        continue;
      }
      if (shown == null) {
        _shown[s.id] = s.position;
        continue;
      }
      final delta = s.position - shown;
      final distance = delta.length;
      _shown[s.id] =
          distance <= step ? s.position : shown + delta * (step / distance);
    }
    final done = <String>[];
    _fading.forEach((id, value) {
      final left = value.$2 - dt * factor;
      if (left <= 0) {
        done.add(id);
      } else {
        _fading[id] = (value.$1, left);
      }
    });
    done.forEach(_fading.remove);
  }

  @override
  void render(Canvas canvas) {
    if (controller.isHidden(squad)) return;
    final isPlayer = squad.side == controller.mySide;
    final base = isPlayer ? BastionColors.laton : BastionColors.cobalto;
    final selected = controller.selectedSquadId == squad.id;
    final active = controller.activeSquadId == squad.id;
    final dimmed = squad.activatedThisRound && !active;
    final fill = Paint()
      ..color = dimmed ? base.withValues(alpha: 0.55) : base;

    final figures = <SoldierDraw>[];
    for (final soldier in squad.alive) {
      final p = _shown[soldier.id] ?? soldier.position;
      final c = Offset(p.x * _ppi, p.y * _ppi);
      final r = soldier.baseRadius * _ppi;
      _drawBase(canvas, c, r, fill, isPlayer);
      figures.add(SoldierDraw(
          center: c,
          radius: r,
          facing: _facing,
          alpha: dimmed ? 0.6 : 1,
          firing: _firingLeft > 0));
    }
    game.renderers.troops.drawFigures(canvas,
        squad: squad, soldiers: figures, teamColor: base, roundBase: isPlayer);

    for (final soldier in squad.alive) {
      final p = _shown[soldier.id] ?? soldier.position;
      final c = Offset(p.x * _ppi, p.y * _ppi);
      final r = soldier.baseRadius * _ppi;
      if (selected || active) {
        canvas.drawCircle(
            c,
            r + 3,
            Paint()
              ..color = active ? BastionColors.latonClaro : BastionColors.tinta
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
    }

    // Bajas: se desvanecen y se hunden un poco, con un aspa de peligro.
    final fallen = <SoldierDraw>[];
    _fading.forEach((id, value) {
      final (p, left) = value;
      final t = left / _fadeTime;
      final soldier = squad.soldiers.firstWhere((s) => s.id == id);
      final c = Offset(p.x * _ppi, p.y * _ppi);
      final r = soldier.baseRadius * _ppi * (0.6 + 0.4 * t);
      _drawBase(canvas, c, r, Paint()..color = base.withValues(alpha: 0.7 * t),
          isPlayer);
      fallen.add(SoldierDraw(
          center: c, radius: r, facing: _facing, alpha: t, fallen: true));
      final cross = Paint()
        ..color = BastionColors.peligro.withValues(alpha: t)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final k = r * 0.8;
      canvas
        ..drawLine(c.translate(-k, -k), c.translate(k, k), cross)
        ..drawLine(c.translate(k, -k), c.translate(-k, k), cross);
    });
    game.renderers.troops.drawFigures(canvas,
        squad: squad, soldiers: fallen, teamColor: base, roundBase: isPlayer);

    if (squad.demoralized && squad.alive.isNotEmpty) {
      final c = squad.centroid;
      canvas.drawCircle(Offset(c.x * _ppi, c.y * _ppi - 18), 4,
          Paint()..color = BastionColors.peligro);
    }
  }

  void _updateFiring(double dt) {
    final c = controller;
    if (c is! BattleController) return;
    if (c.feedVersion != _seenFeed) {
      final first = _seenFeed < 0;
      _seenFeed = c.feedVersion;
      final fired = c.recent
          .any((e) => e is AttackResolved && e.attackerId == squad.id);
      if (!first && fired && c.animationFactor > 0) _firingLeft = 0.4;
    }
    if (_firingLeft > 0) _firingLeft -= dt * c.animationFactor;
  }

  void _updateFacing() {
    if (squad.alive.isEmpty) return;
    final from = squad.centroid;
    double? best;
    for (final other in controller.state.squads) {
      if (other.side == squad.side || other.destroyed || controller.isHidden(other)) {
        continue;
      }
      final to = other.centroid;
      final d = from.distanceTo(to);
      if (best == null || d < best) {
        best = d;
        _facing = math.atan2(to.y - from.y, to.x - from.x);
      }
    }
  }

  void _drawBase(Canvas canvas, Offset c, double r, Paint fill, bool circle) {
    if (circle) {
      canvas.drawCircle(c, r, fill);
      return;
    }
    final diamond = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(diamond, fill);
  }

  /// Centro de la escuadra contando también a los caídos (para efectos que
  /// apuntan a una escuadra recién destruida).
  static Vec2 anchorOf(Squad squad) {
    final soldiers = squad.alive.isNotEmpty ? squad.alive : squad.soldiers;
    var x = 0.0;
    var y = 0.0;
    var n = 0;
    for (final s in soldiers) {
      x += s.position.x;
      y += s.position.y;
      n++;
    }
    return n == 0 ? const Vec2(0, 0) : Vec2(x / n, y / n);
  }
}
