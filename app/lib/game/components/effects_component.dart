import 'dart:ui';

import 'package:flame/components.dart';
import 'package:rules_engine/rules_engine.dart'
    show AttackResolved, ScatterResolved, Vec2;

import '../../art/renderers.dart';

import '../bastion_game.dart';
import '../battle_controller.dart';
import 'squad_component.dart';

/// Efectos de un instante: trazas de disparo y onda del cañón. Se generan
/// con cada lote nuevo de eventos y se escalonan para leerse en orden.
class EffectsComponent extends Component with HasGameReference<BastionGame> {
  EffectsComponent(this.controller) : super(priority: 20);

  final BattleController controller;

  static const double _ppi = BastionGame.pixelsPerInch;
  static const double _stagger = 0.3;

  final List<_Effect> _effects = [];
  int _seenVersion = -1;

  @override
  void onMount() {
    super.onMount();
    // No reproducir lo ocurrido antes de abrir la pantalla.
    _seenVersion = controller.feedVersion;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (controller.feedVersion != _seenVersion) {
      _seenVersion = controller.feedVersion;
      _spawn();
    }
    for (final e in _effects) {
      e.elapsed += dt;
    }
    _effects.removeWhere((e) => e.elapsed > e.delay + e.duration);
  }

  void _spawn() {
    final factor = controller.animationFactor;
    if (factor == 0) return;
    final stagger = _stagger / factor;
    var delay = 0.0;
    for (final event in controller.recent) {
      switch (event) {
        case AttackResolved a:
          final from = SquadComponent.anchorOf(controller.state.squadById(a.attackerId));
          final to = SquadComponent.anchorOf(controller.state.squadById(a.targetId));
          _effects.add(_Tracer(from, to,
              hit: a.hits > 0, delay: delay, speed: factor));
          delay += stagger;
        case ScatterResolved s:
          _effects.add(_Blast(s.landed, delay: delay, speed: factor));
          delay += stagger;
        default:
          break;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    for (final e in _effects) {
      final t = (e.elapsed - e.delay) / e.duration;
      if (t < 0 || t > 1) continue;
      e.draw(canvas, t, _ppi, game.renderers.effects);
    }
  }
}

abstract class _Effect {
  _Effect({required this.delay, required this.duration});

  final double delay;
  final double duration;
  double elapsed = 0;

  /// [t] va de 0 a 1 durante el efecto.
  void draw(Canvas canvas, double t, double ppi, EffectsRenderer renderer);
}

/// Traza que viaja del atacante al objetivo y se apaga.
class _Tracer extends _Effect {
  _Tracer(this.from, this.to,
      {required this.hit, required super.delay, required double speed})
      : super(duration: 0.45 / speed);

  final Vec2 from;
  final Vec2 to;
  final bool hit;

  @override
  void draw(Canvas canvas, double t, double ppi, EffectsRenderer renderer) =>
      renderer.drawTracer(canvas, Offset(from.x * ppi, from.y * ppi),
          Offset(to.x * ppi, to.y * ppi), t,
          hit: hit);
}

/// Onda del disparo de dispersión: radio de 2" que se expande y se apaga.
class _Blast extends _Effect {
  _Blast(this.at, {required super.delay, required double speed})
      : super(duration: 0.7 / speed);

  final Vec2 at;

  @override
  void draw(Canvas canvas, double t, double ppi, EffectsRenderer renderer) =>
      renderer.drawBlast(canvas, Offset(at.x * ppi, at.y * ppi), 2 * ppi, t);
}
