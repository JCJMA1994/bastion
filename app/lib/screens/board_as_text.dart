import 'package:flutter/material.dart';
import 'package:rules_engine/rules_engine.dart' show Squad, Vec2;

import '../game/battle_controller.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

/// Alternativa en texto al tablero, para lector de pantalla o para quien la
/// prefiera: cada escuadra con su posición, distancia y cobertura, y
/// movimientos hacia los objetivos sin necesidad de arrastrar.
class BoardAsText extends StatelessWidget {
  const BoardAsText({super.key, required this.battle});

  final BattleController battle;

  /// "tu flanco, norte" / "centro" / "flanco rival, sur". El flanco propio es
  /// el lado de tu zona de despliegue.
  String _place(Vec2 p) {
    final board = battle.state.board;
    final ownLeft =
        battle.state.mission.deploymentZones(board.width, board.height)[battle.mySide]!.x <
            board.width / 2;
    final third = (p.x / board.width * 3).floor().clamp(0, 2);
    final horizontal = switch (ownLeft ? third : 2 - third) {
      0 => 'tu flanco',
      1 => 'centro',
      _ => 'flanco rival',
    };
    final row = (p.y / board.height * 3).floor().clamp(0, 2);
    final vertical = switch (row) { 0 => 'norte', 1 => 'centro', _ => 'sur' };
    return horizontal == 'centro' && vertical == 'centro'
        ? 'centro del tablero'
        : '$horizontal, $vertical';
  }

  String describe(Squad s) {
    final mine = s.side == battle.mySide;
    final parts = <String>[
      '${s.profile.name} (${mine ? 'tuya' : 'rival'})',
      '${s.aliveCount} de ${s.startingCount} soldados',
      _place(s.centroid),
    ];
    final active = battle.active;
    if (active != null && active.id != s.id) {
      final lof = battle.field.lineOfFire(active, s);
      parts.add('a ${lof.distance.toStringAsFixed(0)} pulgadas');
      if (!mine) {
        parts.add(!lof.visible
            ? 'sin visión'
            : (lof.cover ? 'en cobertura' : 'a la vista'));
      }
    }
    if (s.demoralized) parts.add('Desmoralizada');
    if (s.engagedWith.isNotEmpty) parts.add('trabada en combate');
    if (s.activatedThisRound) parts.add('ya actuó esta ronda');
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final state = battle.state;
    final squads = [
      ...state.aliveSquadsOf(battle.mySide),
      ...state.aliveSquadsOf(battle.mySide.opponent),
    ];
    final objectives = state.board.objectives;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
            header: true, child: Text('TABLERO', style: BastionText.etiqueta())),
        const SizedBox(height: BastionSpace.s1),
        for (final s in squads)
          Semantics(
            button: true,
            selected: battle.selectedSquadId == s.id,
            label: describe(s),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => battle.select(s.id),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: BastionSpace.toqueMin),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: BastionSpace.s1),
                  child: Text(describe(s),
                      style: BastionText.detalle().copyWith(
                          color: battle.selectedSquadId == s.id
                              ? BastionColors.latonClaro
                              : null)),
                ),
              ),
            ),
          ),
        if (battle.canMoveActive) ...[
          const SizedBox(height: BastionSpace.s2),
          Semantics(
              header: true,
              child: Text('MOVER HACIA', style: BastionText.etiqueta())),
          const SizedBox(height: BastionSpace.s1),
          Wrap(
            spacing: BastionSpace.s2,
            runSpacing: BastionSpace.s2,
            children: [
              for (final (i, o) in objectives.indexed)
                SecondaryButton(
                  label: 'Objetivo ${i + 1} (${_place(o.position)})',
                  onPressed: () => battle.moveToward(o.position),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
