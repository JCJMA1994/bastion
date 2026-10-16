import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../copy.dart';
import '../game/bastion_game.dart';
import '../game/deployment_controller.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';
import '../widgets/zoomable_board.dart';

/// Despliegue: elige una escuadra y toca tu zona del tablero para colocarla.
class DeploymentScreen extends StatefulWidget {
  const DeploymentScreen({super.key, required this.app});

  final AppController app;

  @override
  State<DeploymentScreen> createState() => _DeploymentScreenState();
}

class _DeploymentScreenState extends State<DeploymentScreen> {
  late final DeploymentController _controller = widget.app.deployment!;
  late final BastionGame _game =
      BastionGame(controller: _controller, renderers: widget.app.renderers);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Column(
        children: [
          BastionTopBar(
            title: 'DESPLIEGUE',
            subtitle: widget.app.battleTitle,
            onBack: widget.app.isOnlineBattle
                ? widget.app.leaveOnline
                : (widget.app.quickBattle
                    ? widget.app.toMenu
                    : widget.app.openCampaign),
          ),
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
                      child: ZoomableBoard(
                        game: _game,
                        semanticLabel: 'Tablero de despliegue. Usa la lista '
                            'de escuadras y el despliegue automático.',
                      ),
                    ),
                  ),
                  const SizedBox(width: BastionSpace.s3),
                  Expanded(
                    flex: 2,
                    child: BastionPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              widget.app.isOnlineBattle
                                  ? 'Elige una escuadra y toca tu zona. Tu '
                                      'rival no ve dónde la colocas.'
                                  : 'Elige una escuadra y toca tu zona del '
                                      'tablero para colocarla.',
                              style: BastionText.detalle()),
                          const SizedBox(height: BastionSpace.s2),
                          Expanded(
                            child: ListView(
                              children: [
                                for (final s in _controller.ownSquads)
                                  ListTile(
                                    dense: true,
                                    minTileHeight: BastionSpace.toqueMin,
                                    selected: _controller.selectedSquadId == s.id,
                                    selectedTileColor: BastionColors.latonVelo,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            BastionRadius.m)),
                                    title: Text(s.profile.name,
                                        style: BastionText.titulo()),
                                    subtitle: Text('${s.aliveCount} soldados',
                                        style: BastionText.detalle()),
                                    onTap: () => _controller.select(s.id),
                                  ),
                              ],
                            ),
                          ),
                          if (_controller.lastError != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: BastionSpace.s2),
                              child: Text(Copy.violation(_controller.lastError!),
                                  style: BastionText.detalle()
                                      .copyWith(color: BastionColors.peligro)),
                            ),
                          SecondaryButton(
                              label: 'Despliegue automático',
                              onPressed: _controller.autoDeploy),
                          const SizedBox(height: BastionSpace.s2),
                          PrimaryButton(
                            label: widget.app.isOnlineBattle
                                ? 'CONFIRMAR DESPLIEGUE'
                                : 'EMPEZAR BATALLA',
                            onPressed: _controller.isValid
                                ? widget.app.beginBattle
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
