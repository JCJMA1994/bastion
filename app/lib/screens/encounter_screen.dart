import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../copy.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

class EncounterScreen extends StatelessWidget {
  const EncounterScreen({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final run = app.run!;
    final node = run.currentNode!;
    final encounter = app.data.encounters[node.encounterId];
    final resolved = run.completed.contains(node.id);

    return Column(
      children: [
        BastionTopBar(title: 'ENCUENTRO', onBack: app.openCampaign),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(BastionSpace.s4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text((encounter?.title ?? 'Camino tranquilo').toUpperCase(),
                        style: BastionText.seccion()),
                    const SizedBox(height: BastionSpace.s2),
                    Text(encounter?.text ?? 'Nada que reseñar.',
                        style: BastionText.cuerpo()),
                    const SizedBox(height: BastionSpace.s4),
                    if (!resolved && encounter != null)
                      for (final (i, option) in encounter.options.indexed)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: BastionSpace.s2),
                          child: SecondaryButton(
                            label: option.text,
                            onPressed: () => app.chooseEncounterOption(i),
                          ),
                        )
                    else ...[
                      for (final e in app.lastEffects)
                        Text(Copy.effect(e, app.squadLabel),
                            style: BastionText.cuerpo()
                                .copyWith(color: BastionColors.latonClaro)),
                      const SizedBox(height: BastionSpace.s4),
                      PrimaryButton(label: 'CONTINUAR', onPressed: app.openCampaign),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
