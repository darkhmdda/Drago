import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';
import 'dialogs.dart';
import 'import_screen.dart';

class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final active = l.debts.where((d) => d.status == DebtStatus.active).toList();
    final closed = l.debts.where((d) => d.status != DebtStatus.active).toList();

    return PageBody(children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.document_scanner_outlined),
          title: const Text('Importar captura de estado de cuenta'),
          subtitle: const Text('Actualiza cuotas desde una captura de DiDi, Coppel, Mercado Pago…'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
        ),
      ),
      Card(
        child: ListTile(
          title: const Text('Total pendiente de deudas activas'),
          trailing: Text(formatMoney(l.totalPendingDebt),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: FinColors.of(context).expense)),
        ),
      ),
      if (l.debts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Aún no registras deudas.\nUsa el botón “Nueva deuda”.', textAlign: TextAlign.center)),
        ),
      if (active.isNotEmpty) const SectionTitle('Activas'),
      for (final d in active) _DebtCard(summary: l.summaryOf(d.id)),
      if (closed.isNotEmpty) const SectionTitle('Liquidadas y canceladas'),
      for (final d in closed) _DebtCard(summary: l.summaryOf(d.id)),
    ]);
  }
}

class _DebtCard extends StatelessWidget {
  final DebtSummary summary;
  const _DebtCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final d = summary.debt;
    final progress = summary.original == 0 ? 0.0 : (summary.paid / summary.original).clamp(0.0, 1.0);
    final next = summary.installments.where(l.isInstallmentOpen).toList();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: d.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(d.name, style: Theme.of(context).textTheme.titleMedium)),
              StatusChip(d.status.label, d.status == DebtStatus.active ? FinColors.of(context).pending : FinColors.of(context).neutral),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Text('Pagado ${formatMoney(summary.paid)} de ${formatMoney(summary.original)} · pendiente ${formatMoney(summary.remaining)}'),
            if (d.isMonthly)
              Text('Abono mensual de ${formatMoney(d.monthlyPayment!)} el día ${d.paymentDay}', style: Theme.of(context).textTheme.bodySmall),
            if (next.isNotEmpty)
              Text('Próxima cuota: ${formatMoney(l.remainingForInstallment(next.first.id))} · ${fmtDate(next.first.dueDate)}',
                  style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class DebtDetailScreen extends StatelessWidget {
  final String debtId;
  const DebtDetailScreen({super.key, required this.debtId});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    if (!l.debts.any((d) => d.id == debtId)) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('La deuda ya no existe.')));
    }
    final s = l.summaryOf(debtId);
    final d = s.debt;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, v, d),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar deuda')),
              const PopupMenuItem(value: 'import', child: Text('Actualizar desde captura')),
              if (d.status != DebtStatus.cancelled) const PopupMenuItem(value: 'cancel', child: Text('Cancelar deuda')),
              if (d.status == DebtStatus.cancelled) const PopupMenuItem(value: 'reactivate', child: Text('Reactivar deuda')),
              const PopupMenuItem(value: 'delete', child: Text('Eliminar deuda')),
            ],
          ),
        ],
      ),
      floatingActionButton: d.status == DebtStatus.cancelled
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAddInstallmentDialog(context, debtId),
              icon: const Icon(Icons.add),
              label: const Text('Cuota'),
            ),
      body: PageBody(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv('Monto original', formatMoney(s.original)),
              _kv('Total pagado', formatMoney(s.paid), color: FinColors.of(context).income),
              _kv('Saldo pendiente', formatMoney(s.remaining), color: FinColors.of(context).expense, bold: true),
              const Divider(),
              _kv('Suma de cuotas pendientes', formatMoney(s.pendingInstallments)),
              if (d.isMonthly) _kv('Abono mensual', '${formatMoney(d.monthlyPayment!)} el día ${d.paymentDay}'),
              _kv('Inicio', fmtDate(d.startDate)),
              _kv('Estado', d.status.label),
              if (d.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(d.description)),
              if (s.hasMismatch)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'El saldo pendiente (${formatMoney(s.remaining)}) no coincide con la suma de las cuotas pendientes '
                    '(${formatMoney(s.pendingInstallments)}). Puede deberse a cargos, intereses o cuotas aún no registradas.',
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                  ),
                ),
            ]),
          ),
        ),
        SectionTitle('Cuotas (${s.installments.length})'),
        if (s.installments.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Sin cuotas registradas.')),
        for (final i in s.installments) _InstallmentTile(inst: i, debtCancelled: d.status == DebtStatus.cancelled),
      ]),
    );
  }

  Widget _kv(String k, String v, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );

  Future<void> _onMenu(BuildContext context, String v, Debt d) async {
    switch (v) {
      case 'edit':
        await showDebtForm(context, existing: d);
      case 'import':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ImportScreen(debtId: d.id)));
      case 'cancel':
        if (await confirm(context, 'Cancelar deuda', 'La deuda “${d.name}” dejará de contar como pendiente y sus cuotas no aparecerán en la agenda.', danger: true) &&
            context.mounted) {
          await runOp(context, (l) => l.cancelDebt(d.id), success: 'Deuda cancelada');
        }
      case 'reactivate':
        await runOp(context, (l) => l.reactivateDebt(d.id), success: 'Deuda reactivada');
      case 'delete':
        if (await confirm(context, 'Eliminar deuda', 'Se eliminará “${d.name}” y todas sus cuotas. Esta acción no se puede deshacer.',
                action: 'Eliminar', danger: true) &&
            context.mounted) {
          final ok = await runOp(context, (l) => l.deleteDebt(d.id), success: 'Deuda eliminada');
          if (ok && context.mounted) Navigator.pop(context);
        }
    }
  }
}

class _InstallmentTile extends StatelessWidget {
  final Installment inst;
  final bool debtCancelled;
  const _InstallmentTile({required this.inst, required this.debtCancelled});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final status = l.installmentStatus(inst);
    final paid = l.paidForInstallment(inst.id);
    final payments = l.paymentsForInstallment(inst.id);
    final open = l.isInstallmentOpen(inst) && !debtCancelled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 14, child: Text('${inst.number}', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatMoney(inst.amount),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: inst.cancelled ? TextDecoration.lineThrough : null)),
                Text(fmtDate(inst.dueDate), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            StatusChip(status.label, installmentColor(context, status)),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'edit':
                    await showEditInstallmentDialog(context, inst);
                  case 'cancel':
                    await runOp(context, (l) => l.setInstallmentCancelled(inst.id, true), success: 'Cuota cancelada');
                  case 'restore':
                    await runOp(context, (l) => l.setInstallmentCancelled(inst.id, false), success: 'Cuota restaurada');
                  case 'delete':
                    if (await confirm(context, 'Eliminar cuota', '¿Eliminar la cuota ${inst.number} de ${formatMoney(inst.amount)}?',
                            action: 'Eliminar', danger: true) &&
                        context.mounted) {
                      await runOp(context, (l) => l.deleteInstallment(inst.id), success: 'Cuota eliminada');
                    }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar importe / fecha')),
                if (!inst.cancelled) const PopupMenuItem(value: 'cancel', child: Text('Marcar cancelada')),
                if (inst.cancelled) const PopupMenuItem(value: 'restore', child: Text('Restaurar')),
                const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ]),
          if (paid > 0 && status != InstallmentStatus.paid)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 4),
              child: Text('Abonado ${formatMoney(paid)} · falta ${formatMoney(l.remainingForInstallment(inst.id))}'),
            ),
          for (final p in payments)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 2),
              child: Text('✓ ${formatMoney(p.amount)} el ${fmtDate(p.date)} desde ${l.account(p.accountId).name}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: FinColors.of(context).income)),
            ),
          if (open)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => showPayInstallmentDialog(context, inst),
                icon: const Icon(Icons.check),
                label: const Text('Pagar'),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Formulario de deuda. Al crearla permite capturar cuotas de importes distintos.
Future<void> showDebtForm(BuildContext context, {Debt? existing}) async {
  await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _DebtForm(existing: existing)));
}

class _InstRow {
  final TextEditingController amount;
  DateTime date;
  _InstRow(this.date, [String text = '']) : amount = TextEditingController(text: text);
}

class _DebtForm extends StatefulWidget {
  final Debt? existing;
  const _DebtForm({this.existing});
  @override
  State<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<_DebtForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _total = TextEditingController(text: widget.existing == null ? '' : centsToInput(widget.existing!.total));
  late final _desc = TextEditingController(text: widget.existing?.description ?? '');
  late DateTime _start = widget.existing?.startDate ?? DateTime.now();
  late bool _monthly = widget.existing?.isMonthly ?? false;
  late final _payment =
      TextEditingController(text: widget.existing?.monthlyPayment == null ? '' : centsToInput(widget.existing!.monthlyPayment!));
  late final _day = TextEditingController(text: '${widget.existing?.paymentDay ?? DateTime.now().day}');
  final List<_InstRow> _rows = [];

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _total.addListener(_refresh);
  }

  Cents get _rowsSum => _rows.fold<int>(0, (s, r) => s + (parseMoney(r.amount.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final total = parseMoney(_total.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar deuda' : 'Nueva deuda'),
        actions: [TextButton(onPressed: _save, child: const Text('Guardar'))],
      ),
      body: Form(
        key: _formKey,
        child: PageBody(children: [
          TextFormField(
            controller: _name,
            autofocus: !_editing,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'DiDi Préstamos, Mercado Pago, Coppel…', border: OutlineInputBorder()),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe un nombre' : null,
          ),
          gap,
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _monthly,
            onChanged: (v) => setState(() => _monthly = v),
            title: const Text('Abono mensual (sin número fijo de cuotas)'),
            subtitle: const Text('Para tiendas o créditos donde pagas un abono cierto día de cada mes hasta liquidar.'),
          ),
          gap,
          MoneyField(controller: _total, label: _monthly && !_editing ? 'Saldo que debes' : 'Monto total a pagar'),
          gap,
          if (_monthly) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: MoneyField(controller: _payment, label: 'Abono mensual')),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _day,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Día de pago', hintText: '1 a 31', border: OutlineInputBorder()),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return n == null || n < 1 || n > 31 ? 'Del 1 al 31' : null;
                  },
                ),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Drago calcula solo los pagos que faltan hasta cubrir el saldo, y los recalcula si cambias el saldo o el abono.',
                  style: TextStyle(fontSize: 13)),
            ),
            gap,
          ],
          DateField(label: 'Fecha de inicio', value: _start, onChanged: (d) => setState(() => _start = d)),
          gap,
          TextFormField(controller: _desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder())),
          if (!_editing && !_monthly) ...[
            SectionTitle('Cuotas',
                trailing: TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('Agregar cuota'))),
            const Text('Cada cuota puede tener un importe y una fecha diferentes.', style: TextStyle(fontSize: 13)),
            gap,
            for (var k = 0; k < _rows.length; k++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 16, right: 8), child: Text('${k + 1}.')),
                  Expanded(child: MoneyField(controller: _rows[k].amount)),
                  const SizedBox(width: 8),
                  Expanded(child: DateField(label: 'Vence', value: _rows[k].date, onChanged: (d) => setState(() => _rows[k].date = d))),
                  IconButton(onPressed: () => setState(() => _rows.removeAt(k)), icon: const Icon(Icons.close)),
                ]),
              ),
            if (_rows.isNotEmpty)
              Text(
                'Suma de cuotas: ${formatMoney(_rowsSum)}'
                '${total != null && total != _rowsSum ? ' · difiere del monto total (${formatMoney(total)}) — se permite si hay cargos o ajustes' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ]),
      ),
    );
  }

  void _addRow() {
    final last = _rows.isEmpty ? _start : _rows.last.date;
    setState(() => _rows.add(_InstRow(DateTime(last.year, last.month + (_rows.isEmpty ? 0 : 1), last.day))));
    for (final r in _rows) {
      r.amount.removeListener(_refresh);
      r.amount.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final total = parseMoney(_total.text)!;
    final payment = _monthly ? parseMoney(_payment.text) : null;
    final day = _monthly ? int.tryParse(_day.text.trim()) : null;
    if (_monthly && (payment == null || payment <= 0)) {
      showMessage(context, 'Escribe el abono mensual.');
      return;
    }
    final ok = await runOp(context, (l) {
      if (_editing) {
        l.updateDebt(widget.existing!.id,
            name: _name.text,
            total: total,
            startDate: _start,
            description: _desc.text,
            monthlyPayment: payment,
            paymentDay: day,
            clearMonthly: !_monthly && widget.existing!.isMonthly);
      } else {
        l.addDebt(
          name: _name.text,
          total: total,
          startDate: _start,
          description: _desc.text,
          installments: _monthly ? const [] : [for (final r in _rows) (amount: parseMoney(r.amount.text)!, dueDate: r.date)],
          monthlyPayment: payment,
          paymentDay: day,
        );
      }
    }, success: _editing ? 'Deuda actualizada' : 'Deuda registrada');
    if (ok && mounted) Navigator.pop(context);
  }
}
