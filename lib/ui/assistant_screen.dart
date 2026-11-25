import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/assistant.dart';
import '../domain/ledger.dart';
import '../domain/scenarios.dart';
import 'common.dart';
import 'projections_view.dart';

enum _State { open, confirmed, cancelled }

class _Msg {
  final bool fromUser;
  final String? text;
  final AssistantReply? reply;
  _State state = _State.open;
  _Msg.user(this.text)
      : fromUser = true,
        reply = null;
  _Msg.bot(this.reply)
      : fromUser = false,
        text = null;
  _Msg.botText(this.text)
      : fromUser = false,
        reply = null;
}

/// Asistente: escribe en lenguaje normal y Drago propone la operación.
/// Funciona sin IA ni conexión: interpreta con reglas y siempre pide
/// confirmación antes de modificar datos.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[_Msg.botText('Hola. Escríbeme como en un chat: «Hoy gasté 80 en comida», «Recibí 400», '
      '«Pagué DiDi» o «¿Cuánto debo en diciembre?». Antes de cambiar cualquier dato te pediré confirmación.')];
  Scenario? _lastSim;

  static const _suggestions = ['¿Cuánto tengo?', '¿Cuánto debo este mes?', '¿Cuál es mi próximo pago?', 'Recibí 400', 'Simula una semana sin ingresos', 'Ayuda'];

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    _input.clear();
    final reply = interpret(t, AppScope.of(context).ledger);
    setState(() {
      _msgs.add(_Msg.user(t));
      _handle(reply);
    });
    _toBottom();
  }

  void _handle(AssistantReply reply) {
    switch (reply) {
      case CancelSimulationReply():
        _msgs.add(_Msg.botText(_lastSim == null ? 'No hay ninguna simulación activa.' : 'Listo, descarté «${_lastSim!.name}». Tus datos reales siguen igual.'));
        _lastSim = null;
      case SimulationReply(:final scenario):
        _lastSim = scenario;
        _msgs.add(_Msg.bot(reply));
      default:
        _msgs.add(_Msg.bot(reply));
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _confirm(_Msg m, ProposalReply p) async {
    final state = AppScope.of(context);
    try {
      await state.run((l) => p.apply(l));
      setState(() {
        m.state = _State.confirmed;
        _msgs.add(_Msg.botText('✓ ${p.done(state.ledger)}'));
      });
    } on FinanceException catch (e) {
      setState(() {
        m.state = _State.cancelled;
        _msgs.add(_Msg.botText('No se pudo: ${e.message}'));
      });
    }
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente')),
      body: Column(children: [
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                children: [
                  for (final m in _msgs) _bubble(context, m),
                  if (_msgs.length <= 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(color: scheme.surfaceContainer, border: Border(top: BorderSide(color: scheme.outlineVariant))),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Escribe una instrucción…', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(BuildContext context, _Msg m) {
    final scheme = Theme.of(context).colorScheme;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Text(m.text!, style: TextStyle(color: scheme.onPrimaryContainer)),
        ),
      );
    }
    final content = switch (m.reply) {
      null => Text(m.text!),
      AnswerReply(:final text) => Text(text),
      ProposalReply p => _proposal(context, m, p),
      ChoiceReply c => _choice(context, m, c),
      SimulationReply s => _simulation(context, s),
      CancelSimulationReply() => const SizedBox.shrink(),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 32),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
        child: content,
      ),
    );
  }

  Widget _proposal(BuildContext context, _Msg m, ProposalReply p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      for (final d in p.details) Text('• $d'),
      const SizedBox(height: 8),
      switch (m.state) {
        _State.open => Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => _confirm(m, p), child: const Text('Confirmar')),
            TextButton(
              onPressed: () => setState(() {
                m.state = _State.cancelled;
                _msgs.add(_Msg.botText('Cancelado. No cambié nada.'));
              }),
              child: const Text('Cancelar'),
            ),
          ]),
        _State.confirmed => Text('Confirmado', style: TextStyle(color: FinColors.of(context).income, fontWeight: FontWeight.w600)),
        _State.cancelled => Text('Sin cambios', style: TextStyle(color: FinColors.of(context).neutral)),
      },
    ]);
  }

  Widget _choice(BuildContext context, _Msg m, ChoiceReply c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.question),
      const SizedBox(height: 8),
      for (final (label, next) in c.options)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: OutlinedButton(
            onPressed: m.state != _State.open
                ? null
                : () {
                    setState(() {
                      m.state = _State.confirmed;
                      _msgs.add(_Msg.user(label));
                      _handle(next);
                    });
                    _toBottom();
                  },
            child: Text(label, textAlign: TextAlign.left),
          ),
        ),
    ]);
  }

  Widget _simulation(BuildContext context, SimulationReply s) {
    final saved = AppScope.of(context).ledger.scenarios.any((x) => x.id == s.scenario.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.text),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Proyecciones')),
                body: PageBody(children: [ProjectionsView(draft: saved ? null : s.scenario)]),
              ),
            ),
          ),
          icon: const Icon(Icons.show_chart),
          label: const Text('Ver en gráfica'),
        ),
        if (!saved)
          FilledButton.tonalIcon(
            onPressed: () async {
              final ok = await runOp(context, (l) => l.saveScenario(s.scenario), success: 'Simulación guardada');
              if (ok) setState(() {});
            },
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Guardar'),
          )
        else
          Text('Guardada en Reportes → Proyecciones', style: TextStyle(color: FinColors.of(context).income)),
      ]),
    ]);
  }
}
