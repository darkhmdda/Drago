import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/scenarios.dart';
import 'common.dart';
import 'projection_chart.dart';

/// Proyecciones: situación real, proyección base y simulaciones guardadas.
class ProjectionsView extends StatefulWidget {
  /// Simulación sin guardar a mostrar al abrir (la usa el asistente).
  final Scenario? draft;
  const ProjectionsView({super.key, this.draft});
  @override
  State<ProjectionsView> createState() => _ProjectionsViewState();
}

class _ProjectionsViewState extends State<ProjectionsView> {
  int _days = 60;
  String? _selected;
  late Scenario? _draft = widget.draft;

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final fin = FinColors.of(context);
    final base = projectBase(l, days: _days);
    final scenarios = [?_draft, ...l.scenarios];
    final selected = scenarios
        .where((s) => s.id == (_selected ?? _draft?.id))
        .firstOrNull;
    final sim = selected == null ? null : simulate(l, selected, days: _days);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text('Situación real: ${formatMoney(l.totalAvailable)}'),
            subtitle: const Text(
              'Solo dinero confirmado. Las proyecciones y simulaciones nunca cambian este saldo.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 30, label: Text('30 días')),
            ButtonSegment(value: 60, label: Text('60 días')),
            ButtonSegment(value: 90, label: Text('90 días')),
          ],
          selected: {_days},
          onSelectionChanged: (v) => setState(() => _days = v.first),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sim == null
                      ? 'Saldo proyectado'
                      : 'Proyección base vs. «${selected!.name}»',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (base.points.isEmpty &&
                    base.startBalance == 0 &&
                    sim == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Aún no hay nada que proyectar. Registra tu saldo, tus deudas o tus ingresos previstos '
                      '(por ejemplo, tu ingreso semanal) y aquí verás cómo evolucionará tu dinero.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ProjectionChart(
                    series: [
                      ChartSeries('Proyección base', fin.chartBase, base.daily),
                      if (sim != null)
                        ChartSeries(
                          selected!.name,
                          fin.chartScenario,
                          sim.daily,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        _Metrics(base: base, sim: sim, simName: selected?.name),
        if (sim != null && sim.skipped.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Algunos cambios ya no aplican'),
              subtitle: Text(sim.skipped.join('\n')),
            ),
          ),
        SectionTitle(
          'Simulaciones',
          trailing: TextButton.icon(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Nueva'),
          ),
        ),
        const Text(
          'Prueba escenarios («¿y si recibo \$500 semanales?», «¿y si adelanto una cuota?») sin tocar tus datos reales.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        Card(
          child: RadioGroup<String?>(
            groupValue: selected?.id,
            onChanged: (v) => setState(() => _selected = v),
            child: Column(
              children: [
                RadioListTile<String?>(
                  value: null,
                  title: const Text('Solo proyección base'),
                  dense: true,
                  toggleable: false,
                ),
                for (final s in scenarios)
                  RadioListTile<String?>(
                    value: s.id,
                    dense: true,
                    title: Text(
                      s == _draft ? '${s.name} (sin guardar)' : s.name,
                    ),
                    subtitle: Text(
                      s.adjustments.map((a) => a.describe(l)).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondary: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') await _edit(context, s);
                        if (v == 'save' && context.mounted) {
                          final ok = await runOp(
                            context,
                            (l) => l.saveScenario(s),
                            success: 'Simulación guardada',
                          );
                          if (ok) setState(() => _draft = null);
                        }
                        if (v == 'delete' && context.mounted) {
                          if (s == _draft) {
                            setState(() => _draft = null);
                          } else if (await confirm(
                                context,
                                'Eliminar simulación',
                                '¿Eliminar «${s.name}»? Tus datos reales no cambian.',
                                action: 'Eliminar',
                                danger: true,
                              ) &&
                              context.mounted) {
                            await runOp(
                              context,
                              (l) => l.deleteScenario(s.id),
                              success: 'Simulación eliminada',
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        if (s == _draft)
                          const PopupMenuItem(
                            value: 'save',
                            child: Text('Guardar'),
                          ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(s == _draft ? 'Descartar' : 'Eliminar'),
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

  Future<void> _edit(BuildContext context, Scenario? s) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScenarioEditor(existing: s),
      ),
    );
    if (id != null && mounted) {
      setState(() {
        if (_draft != null && _draft!.id == id) _draft = null;
        _selected = id;
      });
    }
  }
}

class _Metrics extends StatelessWidget {
  final ProjectionResult base;
  final ProjectionResult? sim;
  final String? simName;
  const _Metrics({required this.base, required this.sim, this.simName});

  @override
  Widget build(BuildContext context) {
    final fin = FinColors.of(context);
    String minText(ProjectionResult r) =>
        '${formatMoney(r.minimum.$2)}\n${fmtShortDate(r.minimum.$1)}';
    String negText(ProjectionResult r) =>
        r.firstNegative == null ? 'Nunca' : fmtShortDate(r.firstNegative!);
    final rows = <(String, String, String?, Color?)>[
      (
        'Saldo al final',
        formatMoney(base.finalBalance),
        sim == null ? null : formatMoney(sim!.finalBalance),
        null,
      ),
      (
        'Saldo más bajo',
        minText(base),
        sim == null ? null : minText(sim!),
        null,
      ),
      (
        'Saldo negativo desde',
        negText(base),
        sim == null ? null : negText(sim!),
        fin.expense,
      ),
      (
        'Ingresos previstos',
        formatMoney(base.totalIn),
        sim == null ? null : formatMoney(sim!.totalIn),
        null,
      ),
      (
        'Pagos y gastos',
        formatMoney(base.totalOut),
        sim == null ? null : formatMoney(sim!.totalOut),
        null,
      ),
    ];
    final label = Theme.of(context).textTheme.labelMedium;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          columnWidths: sim == null
              ? const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth()}
              : const {
                  0: FlexColumnWidth(1.3),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox(),
                Text('Base', style: label, textAlign: TextAlign.right),
                if (sim != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      sim == null ? '' : (simName ?? 'Simulación'),
                      style: label,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            for (final (k, b, s, warn) in rows)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(k),
                  ),
                  Text(
                    b,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: warn != null && b != 'Nunca' ? warn : null,
                    ),
                  ),
                  if (sim != null)
                    Text(
                      s ?? '',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: warn != null && s != null && s != 'Nunca'
                            ? warn
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Crear o editar una simulación.
class ScenarioEditor extends StatefulWidget {
  final Scenario? existing;
  const ScenarioEditor({super.key, this.existing});
  @override
  State<ScenarioEditor> createState() => _ScenarioEditorState();
}

class _ScenarioEditorState extends State<ScenarioEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final List<ScenarioAdjustment> _adj = [...?widget.existing?.adjustments];

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final base = projectBase(l, days: 60);
    final preview = _adj.isEmpty
        ? null
        : simulate(
            l,
            Scenario(
              id: '',
              name: '',
              createdAt: DateTime.now(),
              adjustments: _adj,
            ),
            days: 60,
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Nueva simulación' : 'Editar simulación',
        ),
        actions: [TextButton(onPressed: _save, child: const Text('Guardar'))],
      ),
      body: PageBody(
        children: [
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej. Diciembre con \$500 semanales',
              border: OutlineInputBorder(),
            ),
          ),
          SectionTitle(
            'Cambios hipotéticos',
            trailing: TextButton.icon(
              onPressed: () => _add(context, l),
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ),
          if (_adj.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Agrega al menos un cambio: un ingreso, un gasto, una semana sin ingresos…',
              ),
            ),
          for (final (i, a) in _adj.indexed)
            Card(
              child: ListTile(
                title: Text(a.describe(l)),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _adj.removeAt(i)),
                ),
              ),
            ),
          if (preview != null) ...[
            const SectionTitle('Vista previa (60 días)'),
            _Metrics(base: base, sim: preview, simName: 'Simulación'),
          ],
          const SizedBox(height: 8),
          const Text(
            'Tus saldos, deudas y movimientos reales no se modifican.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? 'Simulación' : _name.text.trim();
    final s =
        widget.existing?.copyWith(name: name, adjustments: _adj) ??
        Scenario.create(name, _adj, DateTime.now());
    final ok = await runOp(
      context,
      (l) => l.saveScenario(s),
      success: 'Simulación guardada',
    );
    if (ok && mounted) Navigator.pop(context, s.id);
  }

  Future<void> _add(BuildContext context, Ledger l) async {
    final kind = await showModalBottomSheet<AdjustmentKind>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.south_west),
              title: const Text('Ingreso extra o recurrente'),
              onTap: () => Navigator.pop(c, AdjustmentKind.income),
            ),
            ListTile(
              leading: const Icon(Icons.north_east),
              title: const Text('Gasto extraordinario'),
              onTap: () => Navigator.pop(c, AdjustmentKind.expense),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Periodo sin ingresos'),
              onTap: () => Navigator.pop(c, AdjustmentKind.skipIncomes),
            ),
            if (l.recurrences.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('Cambiar un ingreso/gasto recurrente'),
                onTap: () => Navigator.pop(c, AdjustmentKind.changeRecurrence),
              ),
            if (l.openInstallments.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.fast_forward),
                title: const Text('Adelantar o mover una cuota'),
                onTap: () => Navigator.pop(c, AdjustmentKind.moveInstallment),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !context.mounted) return;
    final a = await _askAdjustment(context, l, kind);
    if (a != null) setState(() => _adj.add(a));
  }
}

Future<ScenarioAdjustment?> _askAdjustment(
  BuildContext context,
  Ledger l,
  AdjustmentKind kind,
) {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  final desc = TextEditingController();
  var date = l.today.add(const Duration(days: 1));
  var end = l.today.add(const Duration(days: 7));
  var repeats = false;
  var freq = Frequency.weekly;
  var hasEnd = true;
  String? recurrenceId = l.recurrences.firstOrNull?.id;
  String? installmentId = l.openInstallments.firstOrNull?.id;
  final title = switch (kind) {
    AdjustmentKind.income => 'Ingreso hipotético',
    AdjustmentKind.expense => 'Gasto extraordinario',
    AdjustmentKind.skipIncomes => 'Periodo sin ingresos',
    AdjustmentKind.changeRecurrence => 'Cambiar recurrente',
    AdjustmentKind.moveInstallment => 'Mover una cuota',
  };
  if (kind == AdjustmentKind.moveInstallment && installmentId != null) {
    date = l.today;
  }
  return showFormDialog<ScenarioAdjustment>(
    context,
    title: title,
    formKey: formKey,
    action: 'Agregar',
    onSubmit: () => switch (kind) {
      AdjustmentKind.income => ScenarioAdjustment(
        kind: kind,
        amount: parseMoney(amount.text)!,
        date: date,
        frequency: repeats ? freq : null,
        endDate: repeats && hasEnd ? end : null,
      ),
      AdjustmentKind.expense => ScenarioAdjustment(
        kind: kind,
        amount: parseMoney(amount.text)!,
        date: date,
        description: desc.text.trim(),
      ),
      AdjustmentKind.skipIncomes => ScenarioAdjustment(
        kind: kind,
        date: date,
        endDate: end,
      ),
      AdjustmentKind.changeRecurrence => ScenarioAdjustment(
        kind: kind,
        recurrenceId: recurrenceId,
        amount: parseMoney(amount.text)!,
      ),
      AdjustmentKind.moveInstallment => ScenarioAdjustment(
        kind: kind,
        installmentId: installmentId,
        date: date,
      ),
    },
    builder: (c, setState) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kind == AdjustmentKind.income ||
            kind == AdjustmentKind.expense ||
            kind == AdjustmentKind.changeRecurrence) ...[
          MoneyField(
            controller: amount,
            autofocus: true,
            label: kind == AdjustmentKind.changeRecurrence
                ? 'Nuevo importe'
                : 'Importe',
          ),
          gap,
        ],
        if (kind == AdjustmentKind.expense) ...[
          TextFormField(
            controller: desc,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          gap,
        ],
        if (kind == AdjustmentKind.changeRecurrence)
          DropdownButtonFormField<String>(
            initialValue: recurrenceId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Regla',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final r in l.recurrences)
                DropdownMenuItem(
                  value: r.id,
                  child: Text(
                    '${r.description} · ${formatMoney(r.amount)} · ${r.scheduleLabel.toLowerCase()}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => recurrenceId = v),
          ),
        if (kind == AdjustmentKind.moveInstallment) ...[
          DropdownButtonFormField<String>(
            initialValue: installmentId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cuota',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final i in l.openInstallments)
                DropdownMenuItem(
                  value: i.id,
                  child: Text(
                    '${l.debt(i.debtId).name} · ${i.number} · ${formatMoney(l.remainingForInstallment(i.id))} · ${fmtShortDate(i.dueDate)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => installmentId = v),
          ),
          gap,
        ],
        if (kind != AdjustmentKind.changeRecurrence)
          DateField(
            label: switch (kind) {
              AdjustmentKind.skipIncomes => 'Desde',
              AdjustmentKind.moveInstallment => 'Nueva fecha de pago',
              _ => repeats ? 'Primera fecha' : 'Fecha',
            },
            value: date,
            onChanged: (d) => setState(() => date = d),
          ),
        if (kind == AdjustmentKind.income)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Se repite'),
            value: repeats,
            onChanged: (v) => setState(() => repeats = v),
          ),
        if (kind == AdjustmentKind.income && repeats) ...[
          DropdownButtonFormField<Frequency>(
            initialValue: freq,
            decoration: const InputDecoration(
              labelText: 'Frecuencia',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final f in Frequency.values.where(
                (f) => f != Frequency.custom,
              ))
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (v) => setState(() => freq = v ?? freq),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Hasta una fecha'),
            value: hasEnd,
            onChanged: (v) => setState(() => hasEnd = v ?? false),
          ),
        ],
        if (kind == AdjustmentKind.skipIncomes ||
            (kind == AdjustmentKind.income && repeats && hasEnd)) ...[
          gap,
          DateField(
            label: 'Hasta',
            value: end,
            onChanged: (d) => setState(() => end = d),
          ),
        ],
      ],
    ),
  );
}
