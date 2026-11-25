import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';
import 'debts_screen.dart';
import 'dialogs.dart';

/// Crear un ingreso/gasto previsto (una vez o recurrente) o editar una regla.
Future<void> showScheduledForm(BuildContext context, {bool isIncome = true, Recurrence? editing}) async {
  final formKey = GlobalKey<FormState>();
  var income = editing?.isIncome ?? isIncome;
  final amount = TextEditingController(text: editing == null ? '' : centsToInput(editing.amount));
  final desc = TextEditingController(text: editing?.description ?? '');
  final interval = TextEditingController(text: '${editing?.intervalDays ?? 10}');
  var account = editing?.accountId ?? defaultAccount(context, income ? AccountKind.physical : AccountKind.digital);
  var date = editing?.startDate ?? DateTime.now().add(const Duration(days: 1));
  var repeats = editing != null;
  var freq = editing?.frequency ?? Frequency.weekly;
  DateTime? end = editing?.endDate;

  String preview() => Recurrence(
          id: '',
          description: '',
          amount: 1,
          accountId: '',
          frequency: freq,
          intervalDays: int.tryParse(interval.text) ?? 1,
          startDate: date)
      .scheduleLabel;

  final ok = await showFormDialog<bool>(
    context,
    title: editing != null
        ? 'Editar ${income ? 'ingreso' : 'gasto'} recurrente'
        : (income ? 'Ingreso previsto' : 'Gasto o pago programado'),
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (editing == null) ...[
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Ingreso'), icon: Icon(Icons.south_west)),
            ButtonSegment(value: false, label: Text('Gasto'), icon: Icon(Icons.north_east)),
          ],
          selected: {income},
          onSelectionChanged: (v) => setState(() => income = v.first),
        ),
        gap,
      ],
      Text(
        income
            ? 'Un ingreso previsto NO aumenta tu saldo real hasta que confirmes que lo recibiste.'
            : 'Un gasto programado NO baja tu saldo real hasta que confirmes que lo pagaste.',
        style: const TextStyle(fontSize: 13),
      ),
      if (editing != null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Los cambios aplican a las fechas que aún no confirmas. Lo ya recibido no cambia.',
              style: TextStyle(fontSize: 13)),
        ),
      gap,
      MoneyField(controller: amount, autofocus: editing == null),
      gap,
      TextFormField(
        controller: desc,
        decoration: InputDecoration(
            labelText: 'Descripción',
            hintText: income ? 'Ingreso semanal' : 'Renta, internet, Netflix…',
            border: const OutlineInputBorder()),
      ),
      gap,
      AccountDropdown(
          label: income ? 'Cuenta donde lo recibirás' : 'Cuenta desde la que pagarás',
          value: account,
          onChanged: (v) => setState(() => account = v)),
      gap,
      DateField(label: repeats ? 'Primera fecha' : 'Fecha', value: date, onChanged: (d) => setState(() => date = d)),
      if (editing == null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Se repite'),
          value: repeats,
          onChanged: (v) => setState(() => repeats = v),
        ),
      if (repeats) ...[
        if (editing != null) gap,
        DropdownButtonFormField<Frequency>(
          initialValue: freq,
          decoration: const InputDecoration(labelText: 'Frecuencia', border: OutlineInputBorder()),
          items: [for (final f in Frequency.values) DropdownMenuItem(value: f, child: Text(f.label))],
          onChanged: (v) => setState(() => freq = v ?? freq),
        ),
        if (freq == Frequency.custom) ...[
          gap,
          TextFormField(
            controller: interval,
            decoration: const InputDecoration(labelText: 'Cada cuántos días', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Escribe un número de días' : null,
          ),
        ],
        const SizedBox(height: 6),
        Text('${preview()}${freq == Frequency.biweekly ? '' : ', desde el ${fmtDate(date)}'}',
            style: Theme.of(c).textTheme.bodySmall),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Tiene fecha final'),
          value: end != null,
          onChanged: (v) => setState(() => end = v == true ? DateTime(date.year, date.month + 3, date.day) : null),
        ),
        if (end != null) DateField(label: 'Última fecha', value: end!, onChanged: (d) => setState(() => end = d)),
      ],
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  final days = int.tryParse(interval.text) ?? 7;
  if (editing != null) {
    await runOp(
      context,
      (l) => l.updateRecurrence(editing.id,
          description: desc.text,
          amount: cents,
          accountId: account,
          frequency: freq,
          intervalDays: days,
          startDate: date,
          endDate: end,
          clearEnd: end == null),
      success: 'Regla actualizada',
    );
  } else if (repeats) {
    await runOp(
      context,
      (l) => l.addRecurrence(
          description: desc.text,
          amount: cents,
          accountId: account!,
          frequency: freq,
          startDate: date,
          intervalDays: days,
          endDate: end,
          isIncome: income),
      success: '${income ? 'Ingreso' : 'Gasto'} recurrente creado',
    );
  } else {
    await runOp(
      context,
      (l) => l.addScheduledItem(accountId: account!, amount: cents, date: date, description: desc.text, isIncome: income),
      success: '${income ? 'Ingreso' : 'Gasto'} previsto agregado',
    );
  }
}

String _ensure(Ledger l, CalendarEvent e) =>
    l.ensureScheduledItem(scheduledItemId: e.scheduledItemId, recurrenceId: e.recurrenceId, occurrenceDate: e.occurrenceDate);

/// Confirmar que un ingreso previsto llegó, o que un gasto previsto se pagó.
Future<void> showConfirmScheduledDialog(BuildContext context, CalendarEvent e) async {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController(text: centsToInput(e.amount));
  var date = DateTime.now();
  final l = AppScope.of(context).ledger;
  String? account = e.scheduledItemId != null
      ? l.scheduledItem(e.scheduledItemId!).accountId
      : (e.recurrenceId != null ? l.recurrence(e.recurrenceId!).accountId : null);

  final ok = await showFormDialog<bool>(
    context,
    title: e.isIncome ? 'Confirmar ingreso recibido' : 'Confirmar gasto pagado',
    action: 'Confirmar',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${e.title} · previsto para ${fmtDate(e.date)}'),
      gap,
      MoneyField(controller: amount, label: e.isIncome ? 'Importe recibido' : 'Importe pagado'),
      gap,
      AccountDropdown(value: account, onChanged: (v) => setState(() => account = v)),
      gap,
      DateField(label: e.isIncome ? 'Fecha en que se recibió' : 'Fecha en que se pagó', value: date, onChanged: (d) => setState(() => date = d)),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  await runOp(context, (l) => l.confirmScheduledItem(_ensure(l, e), actualAmount: cents, date: date, accountId: account),
      success: e.isIncome ? 'Ingreso recibido: ${formatMoney(cents)}' : 'Gasto registrado: ${formatMoney(cents)}');
}

/// Ajustar solo esta fecha (importe o día), sin tocar la regla recurrente.
Future<void> showEditOccurrenceDialog(BuildContext context, CalendarEvent e) async {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController(text: centsToInput(e.amount));
  var date = e.date;
  final ok = await showFormDialog<bool>(
    context,
    title: 'Ajustar esta fecha',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(e.title),
      if (e.recurrenceId != null)
        const Text('Solo cambia esta ocurrencia; las demás siguen la regla.', style: TextStyle(fontSize: 13)),
      gap,
      MoneyField(controller: amount),
      gap,
      DateField(value: date, onChanged: (d) => setState(() => date = d)),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  final changes = <String>[
    if (cents != e.amount) 'Importe: ${formatMoney(e.amount)} → ${formatMoney(cents)}',
    if (dayOf(date) != e.date) 'Fecha: ${fmtDate(e.date)} → ${fmtDate(date)}',
  ];
  if (changes.isEmpty) return;
  if (!await confirm(context, 'Confirmar cambios', changes.join('\n'), action: 'Guardar') || !context.mounted) return;
  await runOp(context, (l) => l.updateScheduledItem(_ensure(l, e), amount: cents, date: date), success: 'Actualizado');
}

/// Acciones disponibles para un evento del calendario.
Future<void> showEventActions(BuildContext context, CalendarEvent e) async {
  final l = AppScope.of(context).ledger;
  final color = eventColor(e);
  final actions = <(IconData, String, Future<void> Function())>[];

  if (e.installmentId != null) {
    final inst = l.installment(e.installmentId!);
    if (e.isOpen) actions.add((Icons.check, 'Pagar cuota', () => showPayInstallmentDialog(context, inst)));
    actions.add((Icons.edit_calendar, 'Cambiar importe o fecha', () => showEditInstallmentDialog(context, inst)));
    actions.add((
      Icons.open_in_new,
      'Ver deuda',
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: inst.debtId)))
    ));
  } else {
    if (e.isOpen) {
      actions.add((Icons.check, e.isIncome ? 'Confirmar: ya lo recibí' : 'Confirmar: ya lo pagué', () => showConfirmScheduledDialog(context, e)));
      actions.add((Icons.edit_calendar, 'Ajustar esta fecha', () => showEditOccurrenceDialog(context, e)));
      actions.add((
        Icons.block,
        e.isIncome ? 'No se recibió' : 'Cancelar este gasto',
        () => runOp(context, (l) => l.markScheduledSkipped(_ensure(l, e)),
            success: e.isIncome ? 'Marcado como no recibido' : 'Gasto cancelado'),
      ));
      if (e.recurrenceId == null && e.scheduledItemId != null) {
        actions.add((
          Icons.delete_outline,
          'Eliminar',
          () async {
            if (await confirm(context, 'Eliminar', '¿Eliminar «${e.title}» del ${fmtDate(e.date)}?', action: 'Eliminar', danger: true) &&
                context.mounted) {
              await runOp(context, (l) => l.deleteScheduledItem(e.scheduledItemId!), success: 'Eliminado');
            }
          }
        ));
      }
    }
    if (e.skipped && e.scheduledItemId != null) {
      actions.add((Icons.undo, 'Volver a «previsto»', () => runOp(context, (l) => l.restoreScheduled(e.scheduledItemId!), success: 'Restaurado')));
    }
    if (e.recurrenceId != null && l.recurrences.any((r) => r.id == e.recurrenceId)) {
      final r = l.recurrence(e.recurrenceId!);
      actions.add((Icons.repeat, 'Editar la regla (${r.scheduleLabel.toLowerCase()})', () => showScheduledForm(context, editing: r)));
    }
  }

  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(eventIcon(e), color: color)),
          title: Text(e.title),
          subtitle: Text('${fmtDate(e.date)} · ${e.statusLabel}'),
          trailing: Text(formatMoney(e.signed, signed: true), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ),
        if (e.done)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              e.isIncome
                  ? 'Ya está registrado como recibido. Para deshacerlo, elimina el movimiento en «Movimientos».'
                  : 'Ya está pagado. Para deshacerlo, elimina el movimiento en «Movimientos».',
              style: Theme.of(c).textTheme.bodySmall,
            ),
          ),
        const Divider(),
        for (final (k, a) in actions.indexed) ListTile(leading: Icon(a.$1), title: Text(a.$2), onTap: () => Navigator.pop(c, k)),
      ]),
    ),
  );
  if (picked != null && context.mounted) await actions[picked].$3();
}

Color eventColor(CalendarEvent e) {
  if (e.skipped) return FinColors.neutral;
  if (e.done) return e.isIncome ? FinColors.income : FinColors.paid;
  if (e.overdue && !e.isIncome) return FinColors.expense;
  return e.isIncome ? FinColors.income : FinColors.pending;
}

IconData eventIcon(CalendarEvent e) {
  if (e.skipped) return Icons.block;
  if (e.done) return Icons.check_circle;
  return switch (e.kind) {
    EventKind.income => Icons.south_west,
    EventKind.expense => Icons.north_east,
    EventKind.installment => Icons.credit_card,
  };
}
