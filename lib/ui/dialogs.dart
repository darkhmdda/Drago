import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';
import 'scheduled_dialogs.dart';

const expenseCategories = ['Comida', 'Transporte', 'Servicios', 'Hogar', 'Salud', 'Entretenimiento', 'Compras', 'Otros'];
const incomeCategories = ['Trabajo', 'Ventas', 'Préstamo recibido', 'Regalo', 'Otros'];

String? defaultAccount(BuildContext context, AccountKind kind) {
  final accs = AppScope.of(context).ledger.activeAccounts;
  final match = accs.where((a) => a.kind == kind);
  return match.isNotEmpty ? match.first.id : (accs.isNotEmpty ? accs.first.id : null);
}

/// Registrar ingreso o gasto real.
Future<void> showIncomeExpenseDialog(BuildContext context, {required bool income}) async {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  final desc = TextEditingController();
  var date = DateTime.now();
  var account = defaultAccount(context, AccountKind.physical);
  String? category;
  final cats = income ? incomeCategories : expenseCategories;

  final ok = await showFormDialog<bool>(
    context,
    title: income ? 'Registrar ingreso recibido' : 'Registrar gasto',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
      MoneyField(controller: amount, autofocus: true),
      gap,
      TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder())),
      gap,
      AccountDropdown(value: account, onChanged: (v) => setState(() => account = v)),
      gap,
      DropdownButtonFormField<String>(
        initialValue: category,
        decoration: const InputDecoration(labelText: 'Categoría', border: OutlineInputBorder()),
        items: [for (final c in cats) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => setState(() => category = v),
      ),
      gap,
      DateField(value: date, onChanged: (d) => setState(() => date = d)),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  await runOp(context, (l) {
    if (income) {
      l.addIncome(accountId: account!, amount: cents, date: date, description: desc.text, category: category);
    } else {
      l.addExpense(accountId: account!, amount: cents, date: date, description: desc.text, category: category);
    }
  }, success: income ? 'Ingreso registrado: ${formatMoney(cents)}' : 'Gasto registrado: ${formatMoney(cents)}');
}

Future<void> showTransferDialog(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  final desc = TextEditingController();
  var date = DateTime.now();
  String? from = defaultAccount(context, AccountKind.physical);
  String? to = defaultAccount(context, AccountKind.digital);
  if (to == from) to = null;

  final ok = await showFormDialog<bool>(
    context,
    title: 'Transferencia entre cuentas',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Las transferencias no cuentan como ingreso ni gasto: el total disponible no cambia.',
          style: TextStyle(fontSize: 13)),
      gap,
      MoneyField(controller: amount, autofocus: true),
      gap,
      AccountDropdown(label: 'Desde', value: from, onChanged: (v) => setState(() => from = v)),
      gap,
      AccountDropdown(label: 'Hacia', value: to, excludeId: from, onChanged: (v) => setState(() => to = v)),
      gap,
      TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción (opcional)', border: OutlineInputBorder())),
      gap,
      DateField(value: date, onChanged: (d) => setState(() => date = d)),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  await runOp(context,
      (l) => l.transfer(fromAccountId: from!, toAccountId: to!, amount: cents, date: date, description: desc.text),
      success: 'Transferencia registrada');
}

/// Corregir saldo: la cifra confirmada reemplaza la calculada.
Future<void> showSetBalanceDialog(BuildContext context, Account account) async {
  final l = AppScope.of(context).ledger;
  final current = l.balance(account.id);
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController(text: centsToInput(current));
  final note = TextEditingController();

  final ok = await showFormDialog<bool>(
    context,
    title: 'Corregir saldo · ${account.name}',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Saldo calculado: ${formatMoney(current)}'),
      const SizedBox(height: 4),
      const Text('Escribe cuánto tienes realmente. La diferencia se registrará como ajuste manual.',
          style: TextStyle(fontSize: 13)),
      gap,
      MoneyField(controller: amount, label: 'Saldo real', allowZero: true, autofocus: true),
      gap,
      TextFormField(controller: note, decoration: const InputDecoration(labelText: 'Nota (opcional)', border: OutlineInputBorder())),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  if (cents == current) return;
  final sure = await confirm(context, 'Confirmar corrección',
      '${account.name}: ${formatMoney(current)} → ${formatMoney(cents)}\nAjuste: ${formatMoney(cents - current, signed: true)}');
  if (!sure || !context.mounted) return;
  await runOp(context, (l) => l.setBalance(accountId: account.id, newBalance: cents, note: note.text),
      success: 'Saldo actualizado');
}

/// Flujo del botón de pago de una cuota (sección 2.2):
/// identifica la cuota, muestra importe y fecha, pregunta la cuenta y la fecha
/// real, permite abono parcial y pide confirmación antes de registrar.
Future<void> showPayInstallmentDialog(BuildContext context, Installment inst) async {
  final l = AppScope.of(context).ledger;
  final debt = l.debt(inst.debtId);
  final remaining = l.remainingForInstallment(inst.id);
  final paidSoFar = l.paidForInstallment(inst.id);
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController(text: centsToInput(remaining));
  var date = DateTime.now();
  var account = defaultAccount(context, AccountKind.physical);

  final ok = await showFormDialog<bool>(
    context,
    title: 'Pagar cuota',
    action: 'Continuar',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${debt.name} · cuota ${inst.number}', style: Theme.of(c).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text('Importe: ${formatMoney(inst.amount)} · vence ${fmtDate(inst.dueDate)}'),
      if (paidSoFar > 0) Text('Ya abonado: ${formatMoney(paidSoFar)} · falta ${formatMoney(remaining)}'),
      gap,
      MoneyField(controller: amount, label: 'Importe a pagar (puede ser un abono parcial)'),
      gap,
      AccountDropdown(label: '¿Desde qué cuenta pagaste?', value: account, onChanged: (v) => setState(() => account = v)),
      gap,
      DateField(label: 'Fecha real de pago', value: date, onChanged: (d) => setState(() => date = d)),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  final accName = l.account(account!).name;
  final sure = await confirm(context, 'Confirmar pago',
      '${debt.name} · cuota ${inst.number}\n${formatMoney(cents)} desde $accName el ${fmtDate(date)}.\n\n'
      'Se descontará de tu saldo y se actualizará la deuda.');
  if (!sure || !context.mounted) return;
  await runOp(context,
      (l) => l.payInstallment(installmentId: inst.id, accountId: account!, date: date, amount: cents),
      success: cents >= remaining ? 'Cuota pagada' : 'Abono registrado');
}

/// Edición controlada: muestra el importe/fecha anterior y el nuevo antes de guardar.
Future<void> showEditInstallmentDialog(BuildContext context, Installment inst) async {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController(text: centsToInput(inst.amount));
  var date = inst.dueDate;

  final ok = await showFormDialog<bool>(
    context,
    title: 'Editar cuota ${inst.number}',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
      MoneyField(controller: amount),
      gap,
      DateField(label: 'Vencimiento', value: date, onChanged: (d) => setState(() => date = d)),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  final changes = <String>[
    if (cents != inst.amount) 'Importe: ${formatMoney(inst.amount)} → ${formatMoney(cents)}',
    if (dayOf(date) != inst.dueDate) 'Fecha: ${fmtDate(inst.dueDate)} → ${fmtDate(date)}',
  ];
  if (changes.isEmpty) return;
  final sure = await confirm(context, 'Confirmar cambios', changes.join('\n'), action: 'Guardar');
  if (!sure || !context.mounted) return;
  await runOp(context, (l) => l.updateInstallment(inst.id, amount: cents, dueDate: date), success: 'Cuota actualizada');
}

Future<void> showAddInstallmentDialog(BuildContext context, String debtId) async {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  var date = DateTime.now();
  final ok = await showFormDialog<bool>(
    context,
    title: 'Agregar cuota',
    formKey: formKey,
    onSubmit: () => true,
    builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
      MoneyField(controller: amount, autofocus: true),
      gap,
      DateField(label: 'Vencimiento', value: date, onChanged: (d) => setState(() => date = d)),
    ]),
  );
  if (ok != true || !context.mounted) return;
  final cents = parseMoney(amount.text)!;
  await runOp(context, (l) => l.addInstallment(debtId, amount: cents, dueDate: date), success: 'Cuota agregada');
}

/// Menú de acciones rápidas.
Future<void> showQuickActions(BuildContext context) async {
  final choice = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _SheetLabel('Dinero real'),
          ListTile(leading: Icon(Icons.remove_circle_outline, color: FinColors.of(context).expense), title: const Text('Gasto'), onTap: () => Navigator.pop(c, 0)),
          ListTile(leading: Icon(Icons.add_circle_outline, color: FinColors.of(context).income), title: const Text('Ingreso recibido'), onTap: () => Navigator.pop(c, 1)),
          ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('Transferencia entre cuentas'), onTap: () => Navigator.pop(c, 2)),
          const _SheetLabel('Previsto (no cambia tu saldo)'),
          ListTile(leading: Icon(Icons.schedule, color: FinColors.of(context).income), title: const Text('Ingreso previsto'), subtitle: const Text('Una vez o recurrente (ej. \$400 cada sábado)'), onTap: () => Navigator.pop(c, 3)),
          ListTile(leading: Icon(Icons.event_busy, color: FinColors.of(context).pending), title: const Text('Gasto o pago programado'), subtitle: const Text('Renta, servicios, suscripciones…'), onTap: () => Navigator.pop(c, 4)),
        ]),
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 0:
      await showIncomeExpenseDialog(context, income: false);
    case 1:
      await showIncomeExpenseDialog(context, income: true);
    case 2:
      await showTransferDialog(context);
    case 3:
      await showScheduledForm(context, isIncome: true);
    case 4:
      await showScheduledForm(context, isIncome: false);
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Align(alignment: Alignment.centerLeft, child: Text(text, style: Theme.of(context).textTheme.labelLarge)),
      );
}
