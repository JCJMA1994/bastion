import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../game/bastion_game.dart';
import '../theme/bastion_tokens.dart';
import 'bastion_icons.dart';

/// Tablero con zoom: pellizco con dos dedos, rueda del ratón y botones
/// accesibles (+, −, Ajustar). El arrastre con un dedo sobre zonas vacías lo
/// gestiona el propio tablero.
class ZoomableBoard extends StatefulWidget {
  const ZoomableBoard({super.key, required this.game, this.semanticLabel});

  final BastionGame game;
  final String? semanticLabel;

  @override
  State<ZoomableBoard> createState() => _ZoomableBoardState();
}

class _ZoomableBoardState extends State<ZoomableBoard> {
  final Map<int, Offset> _pointers = {};
  double? _lastSpread;

  BastionGame get game => widget.game;

  double? _spread() {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      game.pinching = true;
      _lastSpread = _spread();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final spread = _spread();
    final last = _lastSpread;
    if (spread != null && last != null && last > 0) {
      game.zoomBy(spread / last);
      _lastSpread = spread;
      setState(() {});
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _lastSpread = null;
      game.pinching = false;
    }
  }

  void _scroll(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      game.zoomBy(e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final zoomed = game.isLoaded && game.zoom > BastionGame.minZoom + 0.01;
    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            label: widget.semanticLabel,
            child: ExcludeSemantics(
              child: Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                onPointerSignal: _scroll,
                child: GameWidget(game: game),
              ),
            ),
          ),
        ),
        Positioned(
          right: BastionSpace.s2,
          bottom: BastionSpace.s2,
          child: Container(
            decoration: BoxDecoration(
              color: BastionColors.mesa900.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(BastionRadius.m),
              border: Border.all(color: BastionColors.mesa600),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Alejar',
                  onPressed: () => setState(() => game.zoomBy(1 / 1.4)),
                  icon: const BastionIcon(BastionIcons.alejar,
                      color: BastionColors.tinta),
                ),
                IconButton(
                  tooltip: 'Acercar',
                  onPressed: () => setState(() => game.zoomBy(1.4)),
                  icon: const BastionIcon(BastionIcons.acercar,
                      color: BastionColors.tinta),
                ),
                if (zoomed)
                  IconButton(
                    tooltip: 'Ver todo el tablero',
                    onPressed: () => setState(game.resetView),
                    icon: const BastionIcon(BastionIcons.ajustar,
                        color: BastionColors.tinta),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Acerca la vista a un punto del mundo (por ejemplo, la escuadra activa).
extension FocusBoard on BastionGame {
  void focusOn(Vector2 world, {double zoomLevel = 2}) =>
      setZoom(zoomLevel, focus: world);
}
