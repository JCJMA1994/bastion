import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../telemetry/telemetry.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

/// Visor de los registros del dispositivo (logs, errores y eventos), con
/// filtro por nivel y copia al portapapeles para adjuntarlos a un informe.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.sink, required this.onBack});

  final MemorySink sink;
  final VoidCallback onBack;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _filter = 'todo';

  bool _matches(TelemetryRecord r) => switch (_filter) {
        'errores' => r.kind == 'error' || r.level == LogLevel.error,
        'avisos' => r.level == LogLevel.warning || r.level == LogLevel.error,
        'eventos' => r.kind == 'event',
        _ => true,
      };

  Color _color(TelemetryRecord r) => switch (r.level) {
        LogLevel.error => BastionColors.peligro,
        LogLevel.warning => BastionColors.laton,
        LogLevel.debug => BastionColors.tintaSuave,
        _ => r.kind == 'event' ? BastionColors.latonClaro : BastionColors.tinta,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sink,
      builder: (context, _) {
        final records = widget.sink.records.where(_matches).toList();
        return Column(
          children: [
            BastionTopBar(
              title: 'REGISTRO',
              subtitle: '${records.length} entradas',
              onBack: widget.onBack,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: records.map((r) => r.toString()).join('\n')));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Registro copiado.')));
                    },
                    child: const Text('Copiar'),
                  ),
                  TextButton(onPressed: widget.sink.clear, child: const Text('Vaciar')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BastionSpace.s2),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'todo', label: Text('Todo')),
                  ButtonSegment(value: 'avisos', label: Text('Avisos')),
                  ButtonSegment(value: 'errores', label: Text('Errores')),
                  ButtonSegment(value: 'eventos', label: Text('Eventos')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
            Expanded(
              child: records.isEmpty
                  ? Center(
                      child: Text('Sin entradas.', style: BastionText.detalle()))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: BastionSpace.s3),
                      itemCount: records.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: BastionColors.mesa600),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: BastionSpace.s1),
                        child: SelectableText(
                          records[i].toString(),
                          style: BastionText.cifra()
                              .copyWith(fontSize: 12, color: _color(records[i])),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
