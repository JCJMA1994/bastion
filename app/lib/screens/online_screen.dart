import 'package:flutter/material.dart';
import 'package:rules_engine/rules_engine.dart' show OrderType;

import '../app/app_controller.dart';
import '../copy.dart';
import '../online/online_client.dart';
import '../online/online_session.dart';
import '../theme/bastion_tokens.dart';
import '../widgets/ui.dart';

/// Sala multijugador: elegir compañía, crear o unirse, y esperar al rival.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key, required this.app});

  final AppController app;

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final session = app.online;
    return Column(
      children: [
        BastionTopBar(title: 'MULTIJUGADOR', onBack: app.leaveOnline),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(BastionSpace.s3),
            child: session != null
                ? _Waiting(session: session)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _RosterBuilder(app: app)),
                      const SizedBox(width: BastionSpace.s3),
                      SizedBox(width: 260, child: _Connect(app: app, code: _code)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.session});

  final OnlineSession session;

  @override
  Widget build(BuildContext context) {
    final (title, line) = switch (session.phase) {
      OnlinePhase.esperandoRival => (
          'CÓDIGO DE PARTIDA',
          'Compártelo con tu rival. El despliegue empieza en cuanto se una.'
        ),
      OnlinePhase.esperandoDespliegue => (
          'DESPLIEGUE ENVIADO',
          'Esperando a que tu rival despliegue. Te avisaremos cuando empiece.'
        ),
      _ => ('PARTIDA', 'Cargando…'),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: BastionText.etiqueta()),
            const SizedBox(height: BastionSpace.s1),
            SelectableText(session.ticket.code,
                style: BastionText.cifra().copyWith(fontSize: 40, letterSpacing: 6)),
            const SizedBox(height: BastionSpace.s2),
            Text(line, style: BastionText.cuerpo()),
            if (session.error != null) ...[
              const SizedBox(height: BastionSpace.s2),
              Text('Sin conexión con el servidor. Reintentando…',
                  style: BastionText.detalle().copyWith(color: BastionColors.peligro)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Connect extends StatelessWidget {
  const _Connect({required this.app, required this.code});

  final AppController app;
  final TextEditingController code;

  @override
  Widget build(BuildContext context) {
    final valid = app.onlineRoster.isValid(app.catalog);
    final busy = app.onlineBusy;
    return BastionPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Partida por turnos: cada uno juega cuando puede.',
              style: BastionText.detalle()),
          const SizedBox(height: BastionSpace.s3),
          PrimaryButton(
              label: 'CREAR PARTIDA',
              onPressed: busy || !valid ? null : app.createOnline),
          const SizedBox(height: BastionSpace.s3),
          TextField(
            controller: code,
            textCapitalization: TextCapitalization.characters,
            style: BastionText.cifra(),
            decoration: const InputDecoration(labelText: 'Código de partida'),
          ),
          const SizedBox(height: BastionSpace.s2),
          SecondaryButton(
            label: 'Unirse',
            onPressed: busy || !valid ? null : () => app.joinOnline(code.text),
          ),
          if (app.onlineError != null) ...[
            const SizedBox(height: BastionSpace.s2),
            Text(app.onlineError!,
                style: BastionText.detalle().copyWith(color: BastionColors.peligro)),
          ],
        ],
      ),
    );
  }
}

/// Elegir hasta 4 escuadras dentro del presupuesto y hasta 3 órdenes.
class _RosterBuilder extends StatelessWidget {
  const _RosterBuilder({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final catalog = app.catalog;
    final roster = app.onlineRoster;
    final cost = roster.cost(catalog);
    final profiles = catalog.all.toList()
      ..sort((a, b) => (a.cost ?? 0).compareTo(b.cost ?? 0));

    void update({List<String>? ids, List<OrderType>? hand}) => app.setOnlineRoster(
        RosterDraft(profileIds: ids ?? roster.profileIds, hand: hand ?? roster.hand));

    return BastionPanel(
      child: ListView(
        children: [
          Row(
            children: [
              Text('TU COMPAÑÍA', style: BastionText.etiqueta()),
              const Spacer(),
              Text(
                '$cost / ${RosterDraft.budget} pts · '
                '${roster.profileIds.length} / ${RosterDraft.maxSquads}',
                style: BastionText.cifra().copyWith(
                    fontSize: 13,
                    color: cost > RosterDraft.budget
                        ? BastionColors.peligro
                        : BastionColors.latonClaro),
              ),
            ],
          ),
          const SizedBox(height: BastionSpace.s2),
          for (final p in profiles)
            Builder(builder: (context) {
              final count = roster.profileIds.where((id) => id == p.id).length;
              final canAdd = roster.profileIds.length < RosterDraft.maxSquads &&
                  (!p.unique || count == 0) &&
                  cost + (p.cost ?? 0) <= RosterDraft.budget;
              return ListTile(
                dense: true,
                minTileHeight: BastionSpace.toqueMin,
                title: Text(p.name, style: BastionText.titulo()),
                subtitle: Text(
                    '${p.unique ? 'Única · gratis' : '${p.cost} pts'} · '
                    '${p.soldiers} soldados',
                    style: BastionText.detalle()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Quitar ${p.name}',
                      onPressed: count == 0
                          ? null
                          : () => update(
                              ids: List.of(roster.profileIds)..remove(p.id)),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('$count', style: BastionText.cifra()),
                    IconButton(
                      tooltip: 'Añadir ${p.name}',
                      onPressed: canAdd
                          ? () => update(ids: [...roster.profileIds, p.id])
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: BastionSpace.s3),
          Text('ÓRDENES (hasta ${RosterDraft.maxHand})', style: BastionText.etiqueta()),
          const SizedBox(height: BastionSpace.s2),
          Wrap(
            spacing: BastionSpace.s2,
            runSpacing: BastionSpace.s2,
            children: [
              for (final o in OrderType.values)
                FilterChip(
                  label: Text('${Copy.order(o)} · ${o.cost} PM'),
                  selected: roster.hand.contains(o),
                  selectedColor: BastionColors.latonVelo,
                  onSelected: (on) {
                    if (on && roster.hand.length >= RosterDraft.maxHand) return;
                    update(
                        hand: on
                            ? [...roster.hand, o]
                            : (List.of(roster.hand)..remove(o)));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
