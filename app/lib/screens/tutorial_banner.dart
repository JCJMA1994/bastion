import 'package:flutter/material.dart';

import '../game/battle_controller.dart';
import '../theme/bastion_tokens.dart';

/// Pasos del tutorial de la primera batalla (textos de la guía de copy). El
/// paso se deduce del estado de la batalla, sin guardar nada aparte.
class TutorialBanner extends StatelessWidget {
  const TutorialBanner({super.key, required this.battle, required this.onSkip});

  final BattleController battle;
  final VoidCallback onSkip;

  static const _steps = [
    'Toca una escuadra para seleccionarla.',
    'Pulsa ACTIVAR para darle órdenes.',
    'Arrastra para moverla. El círculo muestra hasta dónde llega.',
    'Toca un enemigo para ver si puedes dispararle.',
    'Los objetivos dan puntos al final de cada ronda. Pon una escuadra encima.',
  ];

  /// Índice del paso actual, o nulo si el tutorial ya no hace falta.
  int? get step {
    final state = battle.state;
    if (state.round >= 2 || !battle.isPlayerTurn) return null;
    if (battle.enemyTarget != null) return 4;
    if (battle.active != null) {
      return (state.progress?.moved ?? false) ? 3 : 2;
    }
    final selected = battle.selected;
    if (selected != null && selected.side == battle.mySide) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = step;
    if (current == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(BastionSpace.s2),
        padding: const EdgeInsets.fromLTRB(
            BastionSpace.s3, BastionSpace.s1, BastionSpace.s1, BastionSpace.s1),
        decoration: BoxDecoration(
          color: BastionColors.mesa900.withValues(alpha: 0.92),
          border: Border.all(color: BastionColors.laton),
          borderRadius: BorderRadius.circular(BastionRadius.m),
        ),
        child: Row(
          children: [
            Text('${current + 1}/${_steps.length}',
                style: BastionText.cifra()
                    .copyWith(fontSize: 12, color: BastionColors.latonClaro)),
            const SizedBox(width: BastionSpace.s2),
            Expanded(child: Text(_steps[current], style: BastionText.cuerpo())),
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                  foregroundColor: BastionColors.tintaSuave,
                  minimumSize: const Size(44, 44)),
              child: const Text('Saltar'),
            ),
          ],
        ),
      ),
    );
  }
}
