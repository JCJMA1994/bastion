import 'package:flutter/material.dart';
import 'package:rules_engine/rules_engine.dart';

import '../app/app_controller.dart';
import '../copy.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/bastion_icons.dart';
import '../widgets/ui.dart';

/// Mapa de campaña: el siguiente paso se elige entre los nodos disponibles.
class CampaignScreen extends StatefulWidget {
  const CampaignScreen({super.key, required this.app});

  final AppController app;

  @override
  State<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends State<CampaignScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final run = widget.app.run!;
    final available = run.available;
    final selectedId = _selected ?? available.firstOrNull?.id;
    final selected = selectedId == null ? null : run.node(selectedId);

    return Column(
      children: [
        BastionTopBar(
          title: 'CAMPAÑA · DÍA ${run.day}',
          subtitle: available.isEmpty ? null : 'Elige tu próximo paso.',
          onBack: widget.app.toMenu,
          trailing: Text(
            'Compañía ${run.squads.length}  ·  Requisas ${run.requisas}  ·  '
            'Órdenes ${run.hand.length}',
            style: BastionText.detalle(),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(BastionSpace.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: BastionColors.mesa800,
                      border: Border.all(color: BastionColors.mesa600),
                      borderRadius: BorderRadius.circular(BastionRadius.l),
                    ),
                    child: _NodeMap(
                      run: run,
                      selectedId: selectedId,
                      onSelect: (id) => setState(() => _selected = id),
                    ),
                  ),
                ),
                const SizedBox(width: BastionSpace.s3),
                Expanded(
                  flex: 2,
                  child: BastionPanel(
                    child: selected == null
                        ? (run.status == CampaignStatus.enCurso
                            ? _Pending(app: widget.app)
                            : _CampaignOver(app: widget.app))
                        : _NodeDetails(
                            node: selected,
                            canGo: available.contains(selected),
                            onGo: () {
                              _selected = null;
                              widget.app.travel(selected.id);
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeMap extends StatelessWidget {
  const _NodeMap({
    required this.run,
    required this.selectedId,
    required this.onSelect,
  });

  final CampaignRun run;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  static BastionIcons _icon(NodeKind kind) => switch (kind) {
        NodeKind.batalla => BastionIcons.disparar,
        NodeKind.suministros => BastionIcons.suministros,
        NodeKind.encuentro => BastionIcons.encuentro,
        NodeKind.fortin => BastionIcons.atrincherar,
      };

  @override
  Widget build(BuildContext context) {
    final available = run.available.map((n) => n.id).toSet();
    return LayoutBuilder(builder: (context, constraints) {
      Offset at(CampaignNode n) => Offset(
          24 + n.x * (constraints.maxWidth - 48),
          24 + n.y * (constraints.maxHeight - 64));
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgesPainter(
                  run: run, at: at, available: available),
            ),
          ),
          for (final n in run.nodes)
            Positioned(
              left: at(n).dx - 22,
              top: at(n).dy - 22,
              child: _NodeButton(
                node: n,
                icon: _icon(n.kind),
                done: run.completed.contains(n.id),
                current: run.currentNodeId == n.id,
                available: available.contains(n.id),
                selected: selectedId == n.id,
                onTap: () => onSelect(n.id),
              ),
            ),
        ],
      );
    });
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({required this.run, required this.at, required this.available});

  final CampaignRun run;
  final Offset Function(CampaignNode) at;
  final Set<String> available;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in run.nodes) {
      for (final nextId in n.next) {
        final next = run.node(nextId);
        final hot = run.currentNodeId == n.id && available.contains(nextId);
        final travelled =
            run.completed.contains(n.id) && run.completed.contains(nextId);
        canvas.drawLine(
          at(n),
          at(next),
          Paint()
            ..color = hot
                ? BastionColors.laton
                : (travelled ? BastionColors.tintaSuave : BastionColors.mesa500)
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter old) => true;
}

class _NodeButton extends StatelessWidget {
  const _NodeButton({
    required this.node,
    required this.icon,
    required this.done,
    required this.current,
    required this.available,
    required this.selected,
    required this.onTap,
  });

  final CampaignNode node;
  final BastionIcons icon;
  final bool done;
  final bool current;
  final bool available;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch ((current, available, done)) {
      (true, _, _) => (
          BastionColors.laton,
          BastionColors.laton,
          BastionColors.latonTinta
        ),
      (_, true, _) => (
          BastionColors.latonVelo,
          BastionColors.laton,
          BastionColors.latonClaro
        ),
      (_, _, true) => (
          BastionColors.mesa700,
          BastionColors.tintaSuave,
          BastionColors.tintaSuave
        ),
      _ when node.kind == NodeKind.fortin => (
          BastionColors.mesa700,
          BastionColors.peligro,
          BastionColors.peligro
        ),
      _ => (BastionColors.mesa800, BastionColors.mesa500, BastionColors.tintaSuave),
    };
    return Semantics(
      button: true,
      label: '${Copy.nodeKind(node.kind)}'
          '${available ? ', disponible' : ''}${done ? ', completado' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
            boxShadow: selected
                ? const [BoxShadow(color: BastionColors.latonClaro, spreadRadius: 3)]
                : null,
          ),
          child: Center(child: BastionIcon(icon, color: fg)),
        ),
      ),
    );
  }
}

class _NodeDetails extends StatelessWidget {
  const _NodeDetails({required this.node, required this.canGo, required this.onGo});

  final CampaignNode node;
  final bool canGo;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final battle = node.battle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(canGo ? 'PRÓXIMO PASO' : 'MÁS ADELANTE', style: BastionText.etiqueta()),
        const SizedBox(height: BastionSpace.s1),
        Text(Copy.nodeKind(node.kind).toUpperCase(), style: BastionText.seccion()),
        const SizedBox(height: BastionSpace.s2),
        if (battle != null) ...[
          Text(Copy.mission(battle.missionId), style: BastionText.cuerpo()),
          const SizedBox(height: BastionSpace.s2),
          Text('Enemigo: ${battle.enemies.length} escuadras',
              style: BastionText.detalle()),
          if (battle.requisas > 0 || battle.rewardOrder != null)
            Text(
              'Recompensa: '
              '${battle.requisas > 0 ? '+${battle.requisas} requisas' : ''}'
              '${battle.rewardOrder != null ? ' · 1 orden' : ''}',
              style: BastionText.detalle().copyWith(color: BastionColors.latonClaro),
            ),
        ] else if (node.kind == NodeKind.suministros)
          Text('La compañía se recupera y puede reclutar.',
              style: BastionText.cuerpo())
        else
          Text('Algo os espera en el camino.', style: BastionText.cuerpo()),
        const Spacer(),
        PrimaryButton(label: 'AVANZAR', onPressed: canGo ? onGo : null),
      ],
    );
  }
}

class _CampaignOver extends StatelessWidget {
  const _CampaignOver({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final won = app.run!.status == CampaignStatus.victoria;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(won ? 'VICTORIA' : 'DERROTA',
            style: BastionText.seccion()
                .copyWith(fontSize: 40, color: BastionColors.laton)),
        const SizedBox(height: BastionSpace.s2),
        Text(
          won
              ? 'El fortín es vuestro. La frontera, también.'
              : 'La campaña termina aquí. Otra vez será.',
          style: BastionText.cuerpo(),
        ),
        const Spacer(),
        PrimaryButton(label: 'NUEVA CAMPAÑA', onPressed: app.newCampaign),
      ],
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PASO PENDIENTE', style: BastionText.etiqueta()),
        const SizedBox(height: BastionSpace.s2),
        Text('Termina lo que dejaste a medias antes de seguir.',
            style: BastionText.cuerpo()),
        const Spacer(),
        PrimaryButton(label: 'RETOMAR', onPressed: app.resumeNode),
      ],
    );
  }
}
