import 'package:flutter/material.dart';
import 'package:rules_engine/rules_engine.dart';

import '../app/app_controller.dart';
import '../copy.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

/// Elegir hasta 4 escuadras para la batalla del nodo actual.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key, required this.app});

  final AppController app;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  late final Set<String> _chosen = {
    ...widget.app.run!.squads
        .take(CampaignRun.maxSquadsPerBattle)
        .map((s) => s.id),
  };

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final run = app.run!;
    final plan = run.currentNode!.battle!;
    const max = CampaignRun.maxSquadsPerBattle;

    return Column(
      children: [
        BastionTopBar(
          title: 'COMPAÑÍA',
          subtitle: 'Antes de ${app.data.maps[plan.mapId]!.name}',
          onBack: app.openCampaign,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(BastionSpace.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: run.squads.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: BastionSpace.s2),
                    itemBuilder: (context, i) {
                      final s = run.squads[i];
                      final chosen = _chosen.contains(s.id);
                      final profile = app.catalog[s.profileId];
                      return _SquadRow(
                        name: app.squadLabel(s.id),
                        detail: '${profile.role.name[0].toUpperCase()}'
                            '${profile.role.name.substring(1)} · '
                            '${s.soldiers} de ${profile.soldiers} soldados',
                        rank: s.rank,
                        chosen: chosen,
                        onChanged: !chosen && _chosen.length >= max
                            ? null
                            : (value) => setState(() => value
                                ? _chosen.add(s.id)
                                : _chosen.remove(s.id)),
                      );
                    },
                  ),
                ),
                const SizedBox(width: BastionSpace.s3),
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BastionPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PARA ESTA BATALLA',
                                style: BastionText.etiqueta()),
                            const SizedBox(height: BastionSpace.s1),
                            Text('${_chosen.length} / $max escuadras',
                                style: BastionText.cifra().copyWith(fontSize: 22)),
                            const SizedBox(height: BastionSpace.s1),
                            Text(
                                'Las que no vayan descansan y recuperan 1 '
                                'soldado.',
                                style: BastionText.detalle()),
                          ],
                        ),
                      ),
                      const SizedBox(height: BastionSpace.s2),
                      BastionPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ÓRDENES EN MANO', style: BastionText.etiqueta()),
                            const SizedBox(height: BastionSpace.s1),
                            Text(
                              run.hand.isEmpty
                                  ? 'No tienes órdenes. Las ganarás en '
                                      'Suministros y Encuentros.'
                                  : run.hand.map(Copy.order).join(' · '),
                              style: BastionText.cuerpo(),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      PrimaryButton(
                        label: 'A LA BATALLA',
                        onPressed: _chosen.isEmpty
                            ? null
                            : () => app.startDeployment([
                                  for (final s in run.squads)
                                    if (_chosen.contains(s.id)) s.id,
                                ]),
                      ),
                    ],
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

class _SquadRow extends StatelessWidget {
  const _SquadRow({
    required this.name,
    required this.detail,
    required this.rank,
    required this.chosen,
    required this.onChanged,
  });

  final String name;
  final String detail;
  final Rank rank;
  final bool chosen;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: chosen ? BastionColors.latonVelo : BastionColors.mesa700,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BastionRadius.m),
        side: BorderSide(
            color: chosen ? BastionColors.laton : BastionColors.mesa600),
      ),
      child: CheckboxListTile(
        value: chosen,
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: BastionColors.laton,
        checkColor: BastionColors.latonTinta,
        title: Text(name, style: BastionText.titulo()),
        subtitle: Text(detail, style: BastionText.detalle()),
        secondary: rank == Rank.recluta
            ? null
            : Tag(Copy.rank(rank), strong: rank.index >= Rank.veterana.index),
      ),
    );
  }
}
