import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/env.dart';
import '../data/battle_stats.dart';
import '../settings/settings_controller.dart';
import '../settings/sounds.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onBack,
    required this.onReplayTutorial,
    this.stats,
    this.onOpenLogs,
  });

  final SettingsController settings;
  final BattleStats? stats;

  /// Abre el visor de registros; nulo para ocultar la opción.
  final VoidCallback? onOpenLogs;
  final VoidCallback onBack;
  final VoidCallback onReplayTutorial;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        children: [
          BastionTopBar(title: 'AJUSTES', onBack: onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(BastionSpace.s4),
              children: [
                _Section('SONIDO'),
                SwitchListTile(
                  title: Text('Efectos de sonido', style: BastionText.cuerpo()),
                  value: settings.soundOn,
                  activeThumbColor: BastionColors.laton,
                  onChanged: (v) => settings.soundOn = v,
                ),
                ListTile(
                  title: Text('Volumen', style: BastionText.cuerpo()),
                  subtitle: Slider(
                    value: settings.volume,
                    activeColor: BastionColors.laton,
                    label: '${(settings.volume * 100).round()}%',
                    divisions: 10,
                    onChanged: settings.soundOn
                        ? (v) => settings.volume = v
                        : null,
                    onChangeEnd: (_) => Sounds.instance.play(Sfx.dice),
                  ),
                ),
                _Section('ANIMACIONES'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: BastionSpace.s4, vertical: BastionSpace.s2),
                  child: SegmentedButton<AnimationSpeed>(
                    segments: const [
                      ButtonSegment(
                          value: AnimationSpeed.normal, label: Text('Normal')),
                      ButtonSegment(
                          value: AnimationSpeed.rapida, label: Text('Rápidas')),
                      ButtonSegment(
                          value: AnimationSpeed.ninguna,
                          label: Text('Sin animación')),
                    ],
                    selected: {settings.speed},
                    onSelectionChanged: (s) => settings.speed = s.first,
                  ),
                ),
                _Section('ESTILO GRÁFICO'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: BastionSpace.s4, vertical: BastionSpace.s2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<ArtStyle>(
                        segments: const [
                          ButtonSegment(value: ArtStyle.auto, label: Text('Automático')),
                          ButtonSegment(value: ArtStyle.vector, label: Text('Vectorial')),
                          ButtonSegment(value: ArtStyle.sprites, label: Text('Ilustrado')),
                        ],
                        selected: {settings.artStyle},
                        onSelectionChanged: (s) => settings.artStyle = s.first,
                      ),
                      const SizedBox(height: BastionSpace.s1),
                      Text('Se aplica a partir de la próxima batalla.',
                          style: BastionText.detalle()),
                    ],
                  ),
                ),
                _Section('ACCESIBILIDAD'),
                SwitchListTile(
                  title: Text('Texto grande', style: BastionText.cuerpo()),
                  subtitle: Text('Aumenta el texto de toda la app.',
                      style: BastionText.detalle()),
                  value: settings.largeText,
                  activeThumbColor: BastionColors.laton,
                  onChanged: (v) => settings.largeText = v,
                ),
                SwitchListTile(
                  title: Text('Tablero en texto', style: BastionText.cuerpo()),
                  subtitle: Text(
                      'Lista de escuadras con posición, distancia y cobertura. '
                      'Se activa sola con el lector de pantalla.',
                      style: BastionText.detalle()),
                  value: settings.boardAsText,
                  activeThumbColor: BastionColors.laton,
                  onChanged: (v) => settings.boardAsText = v,
                ),
                _Section('PRIVACIDAD'),
                SwitchListTile(
                  title: Text('Informes de errores', style: BastionText.cuerpo()),
                  subtitle: Text('Qué falló y dónde, para arreglarlo.',
                      style: BastionText.detalle()),
                  value: settings.diagnosticsConsent,
                  activeThumbColor: BastionColors.laton,
                  onChanged: (v) => settings.setConsent(
                      diagnostics: v, analytics: settings.analyticsConsent),
                ),
                SwitchListTile(
                  title: Text('Estadísticas de uso', style: BastionText.cuerpo()),
                  subtitle: Text('Pantallas y resultados de batallas, anónimos.',
                      style: BastionText.detalle()),
                  value: settings.analyticsConsent,
                  activeThumbColor: BastionColors.laton,
                  onChanged: (v) => settings.setConsent(
                      diagnostics: settings.diagnosticsConsent, analytics: v),
                ),
                _Section('PARTIDA'),
                ListTile(
                  title: Text('Repetir el tutorial', style: BastionText.cuerpo()),
                  subtitle: Text('Se mostrará en la próxima batalla.',
                      style: BastionText.detalle()),
                  trailing: SecondaryButton(
                      label: 'Repetir', onPressed: onReplayTutorial),
                ),
                if (stats != null) ...[
                  _Section('TUS PARTIDAS'),
                  _StatsTable(stats: stats!),
                ],
                if (onOpenLogs != null) ...[
                  _Section('DIAGNÓSTICO'),
                  ListTile(
                    title: Text('Registro de la app', style: BastionText.cuerpo()),
                    subtitle: Text(
                        'Logs, errores y eventos de este dispositivo.',
                        style: BastionText.detalle()),
                    trailing: SecondaryButton(label: 'Ver', onPressed: onOpenLogs),
                  ),
                ],
                _Section('MULTIJUGADOR'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: BastionSpace.s4),
                  child: TextFormField(
                    initialValue: settings.serverUrl,
                    style: BastionText.cuerpo(),
                    decoration: InputDecoration(
                      labelText: 'Servidor',
                      helperText: 'Por defecto, el servidor local desde el '
                          'emulador de Android.',
                      helperStyle: BastionText.detalle(),
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (v) => settings.serverUrl = v,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(BastionSpace.s4),
                  child: Text(
                    'Bastión ${Env.appVersion} · entorno ${Env.name}',
                    style: BastionText.detalle(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            BastionSpace.s4, BastionSpace.s4, BastionSpace.s4, BastionSpace.s1),
        child: Semantics(header: true, child: Text(text, style: BastionText.etiqueta())),
      );
}

/// Resultados reales por perfil, para contrastar con el simulador.
class _StatsTable extends StatefulWidget {
  const _StatsTable({required this.stats});

  final BattleStats stats;

  @override
  State<_StatsTable> createState() => _StatsTableState();
}

class _StatsTableState extends State<_StatsTable> {
  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    if (stats.totalBattles == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: BastionSpace.s4),
        child: Text('Aún no hay batallas registradas.',
            style: BastionText.detalle()),
      );
    }
    final rows = stats.records.entries.toList()
      ..sort((a, b) => b.value.battles.compareTo(a.value.battles));
    String pct(double v) => '${(v * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BastionSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Table(
            columnWidths: const {0: FlexColumnWidth(2)},
            children: [
              TableRow(children: [
                for (final h in ['Perfil', 'Batallas', 'Victorias', 'Supervivencia'])
                  Text(h, style: BastionText.etiqueta()),
              ]),
              for (final e in rows)
                TableRow(children: [
                  Text(e.key, style: BastionText.cuerpo()),
                  Text('${e.value.battles}', style: BastionText.cifra().copyWith(fontSize: 13)),
                  Text(pct(e.value.winRate), style: BastionText.cifra().copyWith(fontSize: 13)),
                  Text(pct(e.value.averageSurvival),
                      style: BastionText.cifra().copyWith(fontSize: 13)),
                ]),
            ],
          ),
          const SizedBox(height: BastionSpace.s2),
          Wrap(
            spacing: BastionSpace.s2,
            children: [
              SecondaryButton(
                label: 'Copiar datos',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: stats.export()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Datos copiados. Pégalos donde analices el balance.')));
                },
              ),
              SecondaryButton(
                label: 'Borrar',
                onPressed: () => setState(stats.clear),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
