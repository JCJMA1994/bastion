import 'package:flutter/material.dart';
import 'package:rules_engine/rules_engine.dart';

import '../app/app_controller.dart';
import '../copy.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

/// Suministros: la compañía ya se recuperó al llegar; aquí se recluta.
class SuppliesScreen extends StatelessWidget {
  const SuppliesScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final run = app.run!;
    final recruitable = app.catalog.all
        .where((p) => !p.unique && p.cost != null)
        .toList()
      ..sort((a, b) => a.cost!.compareTo(b.cost!));
    final full = run.squads.length >= CampaignRun.maxCompany;

    return Column(
      children: [
        BastionTopBar(
          title: 'SUMINISTROS',
          onBack: app.openCampaign,
          trailing: Text('Requisas ${run.requisas}', style: BastionText.cifra()),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(BastionSpace.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 260,
                  child: BastionPanel(
                    highlighted: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AL LLEGAR',
                            style: BastionText.etiqueta()
                                .copyWith(color: BastionColors.latonClaro)),
                        const SizedBox(height: BastionSpace.s2),
                        for (final e in app.lastEffects)
                          Text(Copy.effect(e, app.squadLabel),
                              style: BastionText.cuerpo()),
                        const Spacer(),
                        PrimaryButton(
                            label: 'CONTINUAR', onPressed: app.openCampaign),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: BastionSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        full
                            ? 'La compañía está completa (${CampaignRun.maxCompany} escuadras).'
                            : 'RECLUTAR · ${run.squads.length} / ${CampaignRun.maxCompany} escuadras',
                        style: BastionText.etiqueta(),
                      ),
                      const SizedBox(height: BastionSpace.s2),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final p in recruitable)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: BastionSpace.s2),
                                child: BastionPanel(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(p.name,
                                                style: BastionText.titulo()),
                                            Text(
                                                '${p.soldiers} soldados · '
                                                'MOV ${p.stats.mov}" · '
                                                'PUN ${p.stats.pun}+',
                                                style: BastionText.detalle()),
                                          ],
                                        ),
                                      ),
                                      SecondaryButton(
                                        label: '${p.cost} requisas',
                                        onPressed: !full &&
                                                run.requisas >= p.cost!
                                            ? () => app.recruit(p.id)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
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
