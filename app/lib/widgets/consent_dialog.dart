import 'package:flutter/material.dart';

import '../theme/bastion_tokens.dart';

/// Petición de consentimiento en el primer arranque. Ambas opciones vienen
/// desactivadas: el jugador decide qué compartir.
Future<({bool diagnostics, bool analytics})?> showConsentDialog(
    BuildContext context) {
  var diagnostics = false;
  var analytics = false;
  return showDialog<({bool diagnostics, bool analytics})>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: BastionColors.mesa700,
        title: Text('Ayúdanos a mejorar Bastión', style: BastionText.titulo()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Puedes compartir datos anónimos con nuestro servidor. No '
                'incluyen tu nombre ni tus contactos, y puedes cambiarlo en '
                'Ajustes cuando quieras.',
                style: BastionText.cuerpo(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: diagnostics,
                activeColor: BastionColors.laton,
                onChanged: (v) => setState(() => diagnostics = v),
                title: Text('Informes de errores', style: BastionText.cuerpo()),
                subtitle: Text('Qué falló y dónde, para arreglarlo.',
                    style: BastionText.detalle()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: analytics,
                activeColor: BastionColors.laton,
                onChanged: (v) => setState(() => analytics = v),
                title: Text('Estadísticas de uso', style: BastionText.cuerpo()),
                subtitle: Text(
                    'Qué pantallas usas y cómo terminan las batallas, para '
                    'equilibrar el juego.',
                    style: BastionText.detalle()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
                context, (diagnostics: false, analytics: false)),
            child: const Text('No compartir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                context, (diagnostics: diagnostics, analytics: analytics)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}
