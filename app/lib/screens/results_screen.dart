import 'package:flutter/material.dart';
import 'package:rules_engine/rules_engine.dart';

import '../app/app_controller.dart';
import '../copy.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/bastion_icons.dart';
import '../widgets/ui.dart';

/// Fin de batalla: resultado, ascensos, bajas, caídas y botín.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final report = app.report!;
    final (title, line) = switch (report.winner) {
      Side.jugador => ('VICTORIA', 'El campo es tuyo. Por ahora.'),
      Side.enemigo => (
          'DERROTA',
          'Retirada ordenada. La compañía sobrevive para otra batalla.'
        ),
      null => ('TABLAS', 'Nadie cede terreno.'),
    };
    final hasLoot = report.requisas > 0 || report.order != null;

    return Padding(
      padding: const EdgeInsets.all(BastionSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: BastionText.seccion().copyWith(
                        fontSize: 56, height: 1, color: BastionColors.laton)),
                const SizedBox(height: BastionSpace.s2),
                Text(line, style: BastionText.cuerpo()),
                const Spacer(),
                if (hasLoot)
                  BastionPanel(
                    highlighted: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BOTÍN',
                            style: BastionText.etiqueta()
                                .copyWith(color: BastionColors.latonClaro)),
                        const SizedBox(height: BastionSpace.s1),
                        Text(
                          [
                            if (report.requisas > 0) '+${report.requisas} requisas',
                            if (report.order != null)
                              'Orden nueva: ${Copy.order(report.order!)}',
                          ].join(' · '),
                          style: BastionText.cuerpo(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: BastionSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('TU COMPAÑÍA', style: BastionText.etiqueta()),
                const SizedBox(height: BastionSpace.s2),
                Expanded(
                  child: ListView(
                    children: [
                      for (final r in report.squads)
                        _ReportRow(name: app.squadLabel(r.squadId), report: r),
                    ],
                  ),
                ),
                const SizedBox(height: BastionSpace.s2),
                PrimaryButton(label: 'CONTINUAR', onPressed: app.openCampaign),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.name, required this.report});

  final String name;
  final SquadReport report;

  @override
  Widget build(BuildContext context) {
    final (icon, color, line) = report.fallen
        ? (
            BastionIcons.bajas,
            BastionColors.peligro,
            'Ha caído. Su veteranía se pierde con ella.'
          )
        : report.promoted
            ? (
                BastionIcons.ascenso,
                BastionColors.laton,
                'Asciende a ${Copy.rank(report.rankAfter)}.'
              )
            : report.rested
                ? (
                    BastionIcons.descanso,
                    BastionColors.tintaSuave,
                    'Descansó y recupera 1 soldado.'
                  )
                : report.soldiersLost > 0
                    ? (
                        BastionIcons.bajas,
                        BastionColors.tintaSuave,
                        'Pierde ${report.soldiersLost} '
                            '${report.soldiersLost == 1 ? 'soldado' : 'soldados'}.'
                      )
                    : (BastionIcons.hecho, BastionColors.exito, 'Sin bajas.');
    return Padding(
      padding: const EdgeInsets.only(bottom: BastionSpace.s2),
      child: BastionPanel(
        child: Row(
          children: [
            BastionIcon(icon, color: color),
            const SizedBox(width: BastionSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: BastionText.titulo()),
                  Text(line,
                      style: BastionText.detalle().copyWith(
                          color: report.fallen ? BastionColors.peligro : null)),
                ],
              ),
            ),
            if (report.experienceGained > 0)
              Text('+${report.experienceGained} vet.',
                  style: BastionText.cifra()
                      .copyWith(fontSize: 13, color: BastionColors.latonClaro)),
          ],
        ),
      ),
    );
  }
}
