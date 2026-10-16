import 'package:flutter/material.dart';
import 'package:rules_engine/rules_engine.dart'
    show
        Abilities,
        AttackOdds,
        AttackResolved,
        DiceRolls,
        HitMode,
        BattleEngine,
        BattleStep,
        GameEvent,
        MoraleChecked,
        ScatterResolved,
        Side,
        Squad,
        SquadDestroyed;

import '../art/renderers.dart';
import '../copy.dart';
import '../game/bastion_game.dart';
import '../game/battle_controller.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/bastion_icons.dart';
import '../settings/settings_controller.dart';
import 'board_as_text.dart';
import '../widgets/zoomable_board.dart';
import 'tutorial_banner.dart';
import '../widgets/ui.dart';

/// Pantalla de batalla: tablero Flame a la izquierda y panel de acciones a la
/// derecha, como en el mockup.
class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    required this.controller,
    required this.title,
    required this.onFinished,
    required this.settings,
    this.renderers = const Renderers.vector(),
    this.showTutorial = false,
    this.onSkipTutorial,
    this.onOpenSettings,
  });

  final SettingsController settings;
  final VoidCallback? onOpenSettings;

  /// Estilo gráfico del tablero en esta batalla.
  final Renderers renderers;

  final BattleController controller;
  final String title;
  final bool showTutorial;
  final VoidCallback? onSkipTutorial;

  /// Se llama al pulsar Continuar con la batalla terminada.
  final VoidCallback onFinished;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late final BastionGame _game =
      BastionGame(controller: widget.controller, renderers: widget.renderers);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final screenReader = MediaQuery.accessibleNavigationOf(context);
    return ListenableBuilder(
          listenable: Listenable.merge([widget.controller, widget.settings]),
          builder: (context, _) {
            widget.controller.animationFactor =
                reduceMotion ? 0 : widget.settings.speed.factor;
            final boardAsText = widget.settings.boardAsText || screenReader;
            return Column(
            children: [
              _TopBar(
                  controller: widget.controller,
                  title: widget.title,
                  onOpenSettings: widget.onOpenSettings),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(BastionSpace.s3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(BastionRadius.l),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ZoomableBoard(
                                  game: _game,
                                  semanticLabel: 'Tablero de batalla. Usa la '
                                      'lista del panel para seleccionar '
                                      'escuadras.',
                                ),
                              ),
                              if (widget.showTutorial)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 0,
                                  child: TutorialBanner(
                                    battle: widget.controller,
                                    onSkip: widget.onSkipTutorial ?? () {},
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: BastionSpace.s3),
                      Expanded(
                        flex: 2,
                        child: _ActionPanel(
                            controller: widget.controller,
                            onFinished: widget.onFinished,
                            boardAsText: boardAsText),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar(
      {required this.controller, required this.title, this.onOpenSettings});

  final BattleController controller;
  final String title;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final me = controller.mySide;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: BastionSpace.s3),
      decoration: const BoxDecoration(
        color: BastionColors.mesa800,
        border: Border(bottom: BorderSide(color: BastionColors.mesa600)),
      ),
      child: Row(
        children: [
          Text('RONDA ${state.round} / ${state.maxRounds}',
              style: BastionText.seccion()),
          const SizedBox(width: BastionSpace.s3),
          Text(title, style: BastionText.detalle()),
          const Spacer(),
          if (onOpenSettings != null)
            IconButton(
              onPressed: onOpenSettings,
              tooltip: 'Ajustes',
              icon: const BastionIcon(BastionIcons.menu,
                  color: BastionColors.tinta),
            ),
          Text('PM ', style: BastionText.etiqueta()),
          Text('${state.commandPoints[me]}', style: BastionText.cifra()),
          const SizedBox(width: BastionSpace.s4),
          Semantics(
            label: 'Puntos de victoria: tú ${state.victoryPoints[me]}, '
                'rival ${state.victoryPoints[me.opponent]}',
            child: ExcludeSemantics(
              child: Row(children: [
                Text('${state.victoryPoints[me]}',
                    style:
                        BastionText.cifra().copyWith(color: BastionColors.laton)),
                Text('  PV  ', style: BastionText.etiqueta()),
                Text('${state.victoryPoints[me.opponent]}',
                    style: BastionText.cifra()
                        .copyWith(color: BastionColors.cobalto)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel(
      {required this.controller,
      required this.onFinished,
      this.boardAsText = false});

  final BattleController controller;
  final VoidCallback onFinished;
  final bool boardAsText;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.step == BattleStep.terminada) {
      return _Result(
          winner: state.winner, me: controller.mySide, onContinue: onFinished);
    }

    final active = controller.active;
    return Container(
      padding: const EdgeInsets.all(BastionSpace.s3),
      decoration: BoxDecoration(
        color: BastionColors.mesa700,
        border: Border.all(color: BastionColors.mesa600),
        borderRadius: BorderRadius.circular(BastionRadius.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BastionSpace.s2),
                      child: Text(
                          'Sin conexión con el servidor. Reintentando…',
                          style: BastionText.detalle()
                              .copyWith(color: BastionColors.peligro)),
                    ),
                  if (!controller.isPlayerTurn &&
                      controller.state.step == BattleStep.activaciones)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BastionSpace.s2),
                      child: Text('Turno del rival…',
                          style: BastionText.detalle()),
                    ),
                  _DiceFeed(controller: controller),
                  if (boardAsText) ...[
                    BoardAsText(battle: controller),
                    const SizedBox(height: BastionSpace.s3),
                  ],
                  _SquadSummary(squad: active ?? controller.selected),
                  if (controller.lastError != null) ...[
                    const SizedBox(height: BastionSpace.s2),
                    Text(Copy.violation(controller.lastError!),
                        style: BastionText.detalle()
                            .copyWith(color: BastionColors.peligro)),
                  ],
                  if (active != null) ...[
                    const SizedBox(height: BastionSpace.s3),
                    _ActivationActions(controller: controller, active: active),
                    if (controller.hand.isNotEmpty) ...[
                      const SizedBox(height: BastionSpace.s3),
                      Text('ÓRDENES', style: BastionText.etiqueta()),
                      const SizedBox(height: BastionSpace.s1),
                      _OrderBar(controller: controller),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: BastionSpace.s2),
          _PrimaryArea(controller: controller),
        ],
      ),
    );
  }
}

class _SquadSummary extends StatelessWidget {
  const _SquadSummary({required this.squad});

  final Squad? squad;

  @override
  Widget build(BuildContext context) {
    final s = squad;
    if (s == null) {
      return Text('Toca una escuadra para seleccionarla.',
          style: BastionText.cuerpo());
    }
    final states = [
      if (s.demoralized) 'Desmoralizada',
      if (s.entrenched) 'Atrincherada',
      if (s.takingCover) 'Cuerpo a tierra',
      if (s.counterAttack) 'Contraataque listo',
      if (s.suppressed) '−2" de MOV',
      if (s.overwatch) 'Vigilando',
      if (s.engagedWith.isNotEmpty) 'Trabada',
    ];
    final stats = s.profile.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.profile.name, style: BastionText.titulo()),
        Text(
          '${s.aliveCount} de ${s.startingCount} soldados'
          '${states.isEmpty ? '' : ' · ${states.join(' · ')}'}',
          style: BastionText.detalle(),
        ),
        const SizedBox(height: BastionSpace.s2),
        Text(
          'MOV ${stats.mov}"  PUN ${stats.pun}+  RES ${stats.res}  '
          'SAL ${stats.sal}+  MOR ${stats.mor}',
          style: BastionText.cifra().copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

class _ActivationActions extends StatelessWidget {
  const _ActivationActions({required this.controller, required this.active});

  final BattleController controller;
  final Squad active;

  @override
  Widget build(BuildContext context) {
    final engaged = active.engagedWith.isNotEmpty;
    final target = controller.enemyTarget;
    final inChargeRange = target != null &&
        controller.field.distance(active, target) <= BattleEngine.chargeRange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.canMoveActive && !engaged)
          Text('Arrastra para moverla. El círculo muestra hasta dónde llega.',
              style: BastionText.detalle()),
        if (target == null && !engaged)
          Text('Toca un enemigo para ver si puedes dispararle.',
              style: BastionText.detalle()),
        if (target != null && !engaged) ...[
          const SizedBox(height: BastionSpace.s2),
          _OddsCard(
            controller: controller,
            showCharge: inChargeRange && !active.demoralized,
          ),
        ],
        const SizedBox(height: BastionSpace.s2),
        Wrap(
          spacing: BastionSpace.s2,
          runSpacing: BastionSpace.s2,
          children: [
            if (controller.canUndo)
              SecondaryButton(
                  label: 'Deshacer movimiento',
                  icon: BastionIcons.deshacer,
                  onPressed: controller.undoMove),
            if (engaged)
              SecondaryButton(
                  label: 'Combatir',
                  icon: BastionIcons.cargar,
                  onPressed: controller.fight),
            if (!engaged && inChargeRange && !active.demoralized)
              SecondaryButton(
                  label: 'Cargar',
                  icon: BastionIcons.cargar,
                  onPressed: controller.charge),
            if (!engaged && controller.field.isNearAnyObjective(active))
              SecondaryButton(
                  label: 'Asegurar',
                  icon: BastionIcons.asegurar,
                  onPressed: controller.secure),
            if (!engaged && controller.canMoveActive)
              SecondaryButton(
                  label: 'Atrincherar',
                  icon: BastionIcons.atrincherar,
                  onPressed: controller.entrench),
            if (!engaged && active.profile.has(Abilities.fortificar))
              SecondaryButton(
                  label: 'Fortificar',
                  icon: BastionIcons.cobertura,
                  onPressed: controller.fortify),
            if (!engaged && controller.canOverwatch)
              SecondaryButton(
                  label: 'Vigilar',
                  icon: BastionIcons.vigilar,
                  onPressed: controller.overwatch),
          ],
        ),
      ],
    );
  }
}

class _OrderBar extends StatelessWidget {
  const _OrderBar({required this.controller});

  final BattleController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: BastionSpace.s2,
      runSpacing: BastionSpace.s2,
      children: [
        for (final order in controller.hand)
          SecondaryButton(
            icon: BastionIcons.ordenes,
            label: '${Copy.order(order)} · ${order.cost} PM',
            onPressed: controller.canAfford(order)
                ? () => controller.playOrder(order)
                : null,
          ),
      ],
    );
  }
}

class _PrimaryArea extends StatelessWidget {
  const _PrimaryArea({required this.controller});

  final BattleController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.active;
    final selected = controller.selected;
    if (active == null) {
      final canActivate = controller.isPlayerTurn &&
          selected != null &&
          selected.side == controller.mySide &&
          !selected.destroyed &&
          !selected.activatedThisRound;
      return PrimaryButton(
        label: 'ACTIVAR',
        onPressed: canActivate ? controller.activateSelected : null,
      );
    }
    final canShoot = controller.enemyTarget != null &&
        active.engagedWith.isEmpty &&
        active.profile.weapons.any((w) => !w.isMelee);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
            label: 'DISPARAR', onPressed: canShoot ? controller.shoot : null),
        const SizedBox(height: BastionSpace.s2),
        SecondaryButton(
            label: 'Terminar activación', onPressed: controller.endActivation),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result(
      {required this.winner, required this.me, required this.onContinue});

  final Side? winner;
  final Side me;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final (title, line) = winner == null
        ? ('TABLAS', 'Nadie cede terreno.')
        : winner == me
            ? ('VICTORIA', 'El campo es tuyo. Por ahora.')
            : (
                'DERROTA',
                'Retirada ordenada. La compañía sobrevive para otra batalla.'
              );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: BastionText.seccion()
                .copyWith(fontSize: 40, color: BastionColors.laton)),
        const SizedBox(height: BastionSpace.s2),
        Text(line, style: BastionText.cuerpo()),
        const SizedBox(height: BastionSpace.s4),
        PrimaryButton(label: 'CONTINUAR', onPressed: onContinue),
      ],
    );
  }
}

/// Resumen animado del último ataque: los pasos aparecen uno tras otro
/// ("8 dados → 5 impactos → 3 heridas → 2 bajas").
class _DiceFeed extends StatelessWidget {
  const _DiceFeed({required this.controller});

  final BattleController controller;

  String _name(String squadId) =>
      controller.state.squadById(squadId).profile.name;

  List<(String, bool)> _lines() {
    final lines = <(String, bool)>[];
    for (final GameEvent e in controller.recent) {
      switch (e) {
        case AttackResolved a:
          final steps = [
            if (a.dice > 0) '${a.dice} dados',
            '${a.hits} ${a.hits == 1 ? 'impacto' : 'impactos'}',
            '${a.wounds} ${a.wounds == 1 ? 'herida' : 'heridas'}',
            '${a.killed} ${a.killed == 1 ? 'baja' : 'bajas'}',
          ];
          lines.add(('${a.reaction ? 'Vigila · ' : ''}'
              '${_name(a.attackerId)} → ${_name(a.targetId)}: '
              '${steps.join(' → ')}', a.killed > 0));
        case ScatterResolved sc:
          lines.add((
            sc.accuracyRoll >= 4
                ? 'Cañón: cae donde apuntaba'
                : 'Cañón: se desvía ${sc.accuracyRoll}"',
            false
          ));
        case MoraleChecked m:
          lines.add((
            '${_name(m.squadId)}: moral ${m.roll} contra ${m.morale} · '
                '${m.passed ? 'resiste' : 'Desmoralizada'}',
            !m.passed
          ));
        case SquadDestroyed d:
          lines.add(('${_name(d.squadId)} destruida', true));
        default:
          break;
      }
    }
    return lines.length > 4 ? lines.sublist(lines.length - 4) : lines;
  }

  /// Tiradas del último ataque con dados, para enseñar sus caras.
  DiceRolls? _lastRolls() {
    for (final e in controller.recent.reversed) {
      if (e is AttackResolved &&
          (e.rolls.hitRolls.isNotEmpty || e.rolls.woundRolls.isNotEmpty)) {
        return e.rolls;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines();
    if (lines.isEmpty) return const SizedBox.shrink();
    final rolls = _lastRolls();
    final factor = controller.animationFactor;
    final faces = rolls == null
        ? null
        : rolls.hitRolls.length + rolls.woundRolls.length + rolls.saveRolls.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: BastionSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _feed(lines),
          if (rolls != null && faces != null && faces > 0)
            TweenAnimationBuilder<double>(
              key: ValueKey('dados-${controller.feedVersion}'),
              tween: Tween(begin: factor == 0 ? faces.toDouble() : 0, end: faces.toDouble()),
              duration: Duration(
                  milliseconds: factor == 0 ? 0 : (60 * faces / factor).round()),
              builder: (context, shown, _) => Padding(
                padding: const EdgeInsets.only(top: BastionSpace.s2),
                child: _DiceFaces(rolls: rolls, shown: shown),
              ),
            ),
        ],
      ),
    );
  }

  Widget _feed(List<(String, bool)> lines) {
    return TweenAnimationBuilder<double>(
        key: ValueKey(controller.feedVersion),
        tween: Tween(begin: 0, end: lines.length.toDouble()),
        duration: Duration(milliseconds: 350 * lines.length),
        builder: (context, shown, _) => Container(
          padding: const EdgeInsets.all(BastionSpace.s2),
          decoration: BoxDecoration(
            color: BastionColors.mesa800,
            borderRadius: BorderRadius.circular(BastionRadius.s),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, (text, bad)) in lines.indexed)
                AnimatedOpacity(
                  opacity: shown > i ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    text,
                    style: BastionText.cifra().copyWith(
                        fontSize: 12,
                        color: bad
                            ? BastionColors.peligro
                            : BastionColors.latonClaro),
                  ),
                ),
            ],
          ),
        ),
    );
  }
}

/// Probabilidades antes de actuar: con qué se impacta, hiere y salva, y qué
/// cabe esperar del disparo (y de la carga, si está a tiro).
class _OddsCard extends StatelessWidget {
  const _OddsCard({required this.controller, required this.showCharge});

  final BattleController controller;
  final bool showCharge;

  @override
  Widget build(BuildContext context) {
    final weapon = controller.activeWeapon;
    final shot = controller.shotOdds;
    final charge = showCharge ? controller.chargeOdds : null;
    final target = controller.enemyTarget!;
    final lines = <Widget>[];

    if (weapon != null && weapon.mode == HitMode.dispersion) {
      lines.add(Text(
          'Cañón: 50% de caer donde apuntas; si no, se desvía 1–3". '
          'Alcanza a todo lo que quede a 2", también a los tuyos.',
          style: BastionText.detalle()));
    } else if (shot != null) {
      lines.addAll(_describe('Disparo', shot));
    }
    if (charge != null) {
      if (lines.isNotEmpty) lines.add(const SizedBox(height: BastionSpace.s2));
      lines.addAll(_describe('Carga', charge));
      if (target.counterAttack) {
        lines.add(Text('Ojo: tiene Contraataque preparado y golpeará primero.',
            style: BastionText.detalle().copyWith(color: BastionColors.peligro)));
      }
    }
    if (target.overwatch) {
      lines.add(Text('Vigila: si te mueves a su alcance, disparará.',
          style: BastionText.detalle().copyWith(color: BastionColors.peligro)));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(BastionSpace.s2),
      decoration: BoxDecoration(
        color: BastionColors.mesa800,
        borderRadius: BorderRadius.circular(BastionRadius.s),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  List<Widget> _describe(String title, AttackOdds odds) => [
        Text(
          '$title · ${odds.dice} dados · impacta ${Copy.target(odds.hitOn, modifier: odds.hitModifier)}'
          ' · hiere ${Copy.target(odds.woundOn, modifier: odds.woundModifier)}'
          ' · ${odds.saveOn == null ? 'sin salvación' : 'salva ${odds.saveOn}+'}',
          style: BastionText.detalle(),
        ),
        Semantics(
          label: '$title: ${Copy.dec(odds.expectedKills)} bajas esperadas, '
              '${Copy.pct(odds.anyKillChance)} de causar al menos una',
          excludeSemantics: true,
          child: Text(
            '≈${Copy.dec(odds.expectedKills)} bajas · '
            '${Copy.pct(odds.anyKillChance)} al menos una'
            '${odds.demoralizeChance >= 0.01 ? ' · ${Copy.pct(odds.demoralizeChance)} desmoraliza' : ''}'
            '${odds.destroyChance >= 0.01 ? ' · ${Copy.pct(odds.destroyChance)} destruye' : ''}',
            style: BastionText.cifra()
                .copyWith(fontSize: 13, color: BastionColors.latonClaro),
          ),
        ),
      ];
}

/// Caras de los dados del último ataque, por fases. Los éxitos del atacante
/// van en latón; las salvaciones conseguidas, con borde.
class _DiceFaces extends StatelessWidget {
  const _DiceFaces({required this.rolls, required this.shown});

  final DiceRolls rolls;

  /// Cuántos dados se han revelado ya (animación).
  final double shown;

  @override
  Widget build(BuildContext context) {
    var index = 0;
    Widget row(String label, List<int> values, bool Function(int) success,
        {bool defender = false}) {
      if (values.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: BastionSpace.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 92, child: Text(label, style: BastionText.etiqueta())),
            Expanded(
              child: Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (final v in values)
                    _Die(
                      value: v,
                      success: success(v),
                      defender: defender,
                      visible: shown > index++,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    bool ok(int v, int? on, int mod) =>
        on == null || (v != 1 && (v == 6 || v + mod >= on));

    return Semantics(
      label: 'Dados: ${rolls.hitRolls.join(', ')} para impactar; '
          '${rolls.woundRolls.join(', ')} para herir; '
          '${rolls.saveRolls.isEmpty ? 'sin salvaciones' : '${rolls.saveRolls.join(', ')} para salvar'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('IMPACTA ${Copy.target(rolls.hitOn, modifier: rolls.hitModifier)}',
              rolls.hitRolls, (v) => ok(v, rolls.hitOn, rolls.hitModifier)),
          row('HIERE ${Copy.target(rolls.woundOn, modifier: rolls.woundModifier)}',
              rolls.woundRolls, (v) => ok(v, rolls.woundOn, rolls.woundModifier)),
          row('SALVA ${rolls.saveOn ?? '—'}+', rolls.saveRolls,
              (v) => ok(v, rolls.saveOn, 0),
              defender: true),
        ],
      ),
    );
  }
}

class _Die extends StatelessWidget {
  const _Die({
    required this.value,
    required this.success,
    required this.defender,
    required this.visible,
  });

  final int value;
  final bool success;
  final bool defender;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final bg = success && !defender ? BastionColors.laton : BastionColors.mesa700;
    final fg = success && !defender
        ? BastionColors.latonTinta
        : (success ? BastionColors.tinta : BastionColors.tintaSuave);
    return AnimatedScale(
      scale: visible ? 1 : 0.4,
      duration: const Duration(milliseconds: 150),
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: success && defender ? BastionColors.tinta : Colors.transparent),
          ),
          child: Text('$value',
              style: BastionText.cifra().copyWith(fontSize: 12, color: fg, height: 1)),
        ),
      ),
    );
  }
}
