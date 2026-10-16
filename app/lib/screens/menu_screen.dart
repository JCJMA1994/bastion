import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../widgets/consent_dialog.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.app});

  final AppController app;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  AppController get app => widget.app;

  @override
  void initState() {
    super.initState();
    // Primer arranque: se pide el consentimiento antes de enviar nada.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || app.settings.consentDecided) return;
      final answer = await showConsentDialog(context);
      if (answer == null) return;
      app.settings.setConsent(
          diagnostics: answer.diagnostics, analytics: answer.analytics);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (app.updateRequired) return const _UpdateRequired();
    return Padding(
      padding: const EdgeInsets.all(BastionSpace.s6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BASTIÓN',
                    style: BastionText.seccion()
                        .copyWith(fontSize: 64, height: 1, letterSpacing: 1.3)),
                const SizedBox(height: BastionSpace.s2),
                Text('Escaramuzas tácticas sobre la mesa de guerra.',
                    style: BastionText.cuerpo()
                        .copyWith(color: BastionColors.tintaSuave)),
                if (app.maintenanceMessage.isNotEmpty) ...[
                  const SizedBox(height: BastionSpace.s4),
                  BastionPanel(
                    highlighted: true,
                    child: Text(app.maintenanceMessage,
                        style: BastionText.cuerpo()),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 280,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (app.canContinue) ...[
                  PrimaryButton(label: 'CONTINUAR', onPressed: app.resumeNode),
                  const SizedBox(height: BastionSpace.s2),
                  SecondaryButton(
                      label: 'Nueva campaña',
                      onPressed: () => _confirmNew(context)),
                ] else
                  PrimaryButton(
                      label: 'NUEVA CAMPAÑA', onPressed: app.newCampaign),
                const SizedBox(height: BastionSpace.s2),
                if (app.quickBattleEnabled)
                  SecondaryButton(
                      label: 'Batalla rápida', onPressed: app.startQuickBattle),
                if (app.multiplayerEnabled) ...[
                  const SizedBox(height: BastionSpace.s2),
                  SecondaryButton(
                      label: 'Multijugador', onPressed: app.openOnline),
                ],
                const SizedBox(height: BastionSpace.s2),
                SecondaryButton(label: 'Ajustes', onPressed: app.openSettings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmNew(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BastionColors.mesa700,
        title: Text('¿Empezar otra campaña?', style: BastionText.titulo()),
        content: Text('La campaña actual se perderá.',
            style: BastionText.cuerpo()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir con la actual')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Empezar otra')),
        ],
      ),
    );
    if (ok ?? false) app.newCampaign();
  }
}

/// La configuración remota exige una versión más nueva.
class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(BastionSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ACTUALIZA BASTIÓN', style: BastionText.seccion()),
              const SizedBox(height: BastionSpace.s2),
              Text(
                'Esta versión ya no es compatible con el servidor. Descarga '
                'la última desde la tienda para seguir jugando. Tu campaña '
                'está guardada.',
                style: BastionText.cuerpo(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
