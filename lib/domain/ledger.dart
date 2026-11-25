import 'package:uuid/uuid.dart';

import 'models.dart';
import 'money.dart';

/// Error de validación de una operación financiera. Cuando se lanza,
/// ningún dato ha sido modificado (las operaciones son atómicas).
class FinanceException implements Exception {
  final String message;
  FinanceException(this.message);
  @override
  String toString() => message;
}

/// Resumen calculado de una deuda.
class DebtSummary {
  final Debt debt;
  final List<Installment> installments;

  /// Monto original de la deuda.
  Cents get original => debt.total;

  /// Total efectivamente pagado (suma de abonos registrados).
  final Cents paid;

  /// Saldo pendiente según el monto original: original - pagado.
  Cents get remaining => original - paid;

  /// Suma de lo que falta pagar de las cuotas no canceladas.
  final Cents pendingInstallments;

  /// El monto original y la suma de las cuotas pueden no coincidir
  /// (cargos, ajustes, intereses). La app no asume que coinciden.
  bool get hasMismatch => remaining != pendingInstallments;

  DebtSummary({required this.debt, required this.installments, required this.paid, required this.pendingInstallments});
}

/// Evento que aparece en la agenda (cuota pendiente o ingreso previsto).
class AgendaItem {
  final DateTime date;
  final String title;
  final Cents amount;
  final bool isIncome;
  final String statusLabel;
  final String? installmentId;
  final String? scheduledIncomeId;

  const AgendaItem({
    required this.date,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.statusLabel,
    this.installmentId,
    this.scheduledIncomeId,
  });
}

class MonthSummary {
  final Cents income;
  final Cents expenses;
  final Cents debtPayments;
  const MonthSummary(this.income, this.expenses, this.debtPayments);
  Cents get net => income - expenses - debtPayments;
}

/// Motor financiero. Contiene todos los datos y las únicas operaciones
/// autorizadas para modificarlos. Es Dart puro (sin Flutter) para poder
/// probarse y reutilizarse (por ejemplo, por un futuro asistente de IA).
///
/// Regla de atomicidad: cada operación valida TODO antes de modificar algo.
class Ledger {
  static const schemaVersion = 1;
  static const _uuid = Uuid();

  final List<Account> accounts;
  final List<Transaction> transactions;
  final List<Debt> debts;
  final List<Installment> installments;
  final List<ScheduledIncome> scheduledIncomes;
  final List<AuditEntry> auditLog;

  /// Reloj inyectable (para pruebas).
  DateTime Function() clock;

  Ledger({
    List<Account>? accounts,
    List<Transaction>? transactions,
    List<Debt>? debts,
    List<Installment>? installments,
    List<ScheduledIncome>? scheduledIncomes,
    List<AuditEntry>? auditLog,
    DateTime Function()? clock,
  })  : accounts = accounts ?? [],
        transactions = transactions ?? [],
        debts = debts ?? [],
        installments = installments ?? [],
        scheduledIncomes = scheduledIncomes ?? [],
        auditLog = auditLog ?? [],
        clock = clock ?? DateTime.now;

  /// Datos iniciales: una cuenta de efectivo y una digital, en cero.
  factory Ledger.withDefaults({DateTime Function()? clock}) {
    final l = Ledger(clock: clock);
    l.createAccount('Efectivo', AccountKind.physical);
    l.createAccount('Banco / tarjeta', AccountKind.digital);
    return l;
  }

  DateTime get today => dayOf(clock());
  String _id() => _uuid.v4();

  void _audit(String action, String details) {
    auditLog.add(AuditEntry(id: _id(), at: clock(), action: action, details: details));
  }

  // -------------------------------------------------------------------------
  // Búsquedas
  // -------------------------------------------------------------------------

  Account account(String id) =>
      accounts.firstWhere((a) => a.id == id, orElse: () => throw FinanceException('La cuenta no existe.'));
  Debt debt(String id) => debts.firstWhere((d) => d.id == id, orElse: () => throw FinanceException('La deuda no existe.'));
  Installment installment(String id) =>
      installments.firstWhere((i) => i.id == id, orElse: () => throw FinanceException('La cuota no existe.'));
  ScheduledIncome scheduledIncome(String id) => scheduledIncomes.firstWhere((s) => s.id == id,
      orElse: () => throw FinanceException('El ingreso previsto no existe.'));

  List<Account> get activeAccounts => accounts.where((a) => !a.archived).toList();

  // -------------------------------------------------------------------------
  // Saldos (solo dinero real confirmado)
  // -------------------------------------------------------------------------

  Cents balance(String accountId, {DateTime? asOf}) {
    var total = 0;
    for (final t in transactions) {
      if (asOf != null && t.date.isAfter(asOf)) continue;
      total += t.effectOn(accountId);
    }
    return total;
  }

  Cents totalByKind(AccountKind kind, {DateTime? asOf}) =>
      accounts.where((a) => a.kind == kind).fold<int>(0, (s, a) => s + balance(a.id, asOf: asOf));

  Cents get physicalTotal => totalByKind(AccountKind.physical);
  Cents get digitalTotal => totalByKind(AccountKind.digital);

  /// Total disponible = dinero físico + dinero digital.
  /// Nunca incluye ingresos previstos ni dinero por cobrar.
  Cents get totalAvailable => physicalTotal + digitalTotal;

  // -------------------------------------------------------------------------
  // Cuentas
  // -------------------------------------------------------------------------

  Account createAccount(String name, AccountKind kind, {Cents initialBalance = 0}) {
    final n = name.trim();
    if (n.isEmpty) throw FinanceException('La cuenta necesita un nombre.');
    if (initialBalance < 0) throw FinanceException('El saldo inicial no puede ser negativo.');
    final acc = Account(id: _id(), name: n, kind: kind);
    accounts.add(acc);
    _audit('Cuenta creada', '${acc.name} (${kind.label})');
    if (initialBalance != 0) {
      transactions.add(Transaction(
        id: _id(),
        date: today,
        amount: initialBalance,
        type: TxType.adjustment,
        description: 'Saldo inicial',
        accountId: acc.id,
        createdAt: clock(),
      ));
    }
    return acc;
  }

  void renameAccount(String id, String name) {
    final acc = account(id);
    final n = name.trim();
    if (n.isEmpty) throw FinanceException('La cuenta necesita un nombre.');
    accounts[accounts.indexOf(acc)] = acc.copyWith(name: n);
    _audit('Cuenta renombrada', '${acc.name} → $n');
  }

  void setAccountArchived(String id, bool archived) {
    final acc = account(id);
    if (archived && balance(id) != 0) {
      throw FinanceException('Solo se pueden archivar cuentas con saldo cero.');
    }
    if (archived && activeAccounts.where((a) => a.kind == acc.kind).length <= 1) {
      throw FinanceException('Debe quedar al menos una cuenta de tipo ${acc.kind.label.toLowerCase()}.');
    }
    accounts[accounts.indexOf(acc)] = acc.copyWith(archived: archived);
    _audit(archived ? 'Cuenta archivada' : 'Cuenta restaurada', acc.name);
  }

  // -------------------------------------------------------------------------
  // Movimientos
  // -------------------------------------------------------------------------

  void _requirePositive(Cents amount) {
    if (amount <= 0) throw FinanceException('El importe debe ser mayor que cero.');
  }

  Transaction _addTx(Transaction t) {
    transactions.add(t);
    return t;
  }

  Transaction addIncome({
    required String accountId,
    required Cents amount,
    required DateTime date,
    String description = 'Ingreso',
    String? category,
  }) {
    _requirePositive(amount);
    account(accountId);
    final t = _addTx(Transaction(
      id: _id(),
      date: dayOf(date),
      amount: amount,
      type: TxType.income,
      description: description.trim().isEmpty ? 'Ingreso' : description.trim(),
      accountId: accountId,
      category: category,
      createdAt: clock(),
    ));
    _audit('Ingreso registrado', '${t.description}: ${formatMoney(amount)}');
    return t;
  }

  Transaction addExpense({
    required String accountId,
    required Cents amount,
    required DateTime date,
    String description = 'Gasto',
    String? category,
  }) {
    _requirePositive(amount);
    account(accountId);
    final t = _addTx(Transaction(
      id: _id(),
      date: dayOf(date),
      amount: amount,
      type: TxType.expense,
      description: description.trim().isEmpty ? 'Gasto' : description.trim(),
      accountId: accountId,
      category: category,
      createdAt: clock(),
    ));
    _audit('Gasto registrado', '${t.description}: ${formatMoney(amount)}');
    return t;
  }

  /// Transferencia entre cuentas propias: no es ingreso ni gasto, el total no cambia.
  Transaction transfer({
    required String fromAccountId,
    required String toAccountId,
    required Cents amount,
    required DateTime date,
    String description = 'Transferencia',
  }) {
    _requirePositive(amount);
    if (fromAccountId == toAccountId) throw FinanceException('Elige dos cuentas distintas.');
    final from = account(fromAccountId);
    final to = account(toAccountId);
    final t = _addTx(Transaction(
      id: _id(),
      date: dayOf(date),
      amount: amount,
      type: TxType.transfer,
      description: description.trim().isEmpty ? 'Transferencia' : description.trim(),
      accountId: fromAccountId,
      toAccountId: toAccountId,
      createdAt: clock(),
    ));
    _audit('Transferencia', '${from.name} → ${to.name}: ${formatMoney(amount)}');
    return t;
  }

  /// Corrección de saldo: la cifra confirmada reemplaza el cálculo anterior.
  /// Se registra como ajuste manual por la diferencia, para que quede rastro.
  Transaction? setBalance({required String accountId, required Cents newBalance, DateTime? date, String? note}) {
    final acc = account(accountId);
    final current = balance(accountId);
    final diff = newBalance - current;
    if (diff == 0) return null;
    final t = _addTx(Transaction(
      id: _id(),
      date: dayOf(date ?? clock()),
      amount: diff,
      type: TxType.adjustment,
      description: (note == null || note.trim().isEmpty) ? 'Corrección de saldo' : note.trim(),
      accountId: accountId,
      createdAt: clock(),
    ));
    _audit('Corrección de saldo', '${acc.name}: ${formatMoney(current)} → ${formatMoney(newBalance)}');
    return t;
  }

  /// Elimina un movimiento. Si era un pago de cuota, la cuota vuelve a quedar
  /// pendiente; si venía de un ingreso previsto, este vuelve a "previsto".
  void deleteTransaction(String id) {
    final t = transactions.firstWhere((x) => x.id == id,
        orElse: () => throw FinanceException('El movimiento no existe.'));
    transactions.remove(t);
    if (t.scheduledItemId != null) {
      final idx = scheduledIncomes.indexWhere((s) => s.id == t.scheduledItemId);
      if (idx >= 0) {
        scheduledIncomes[idx] =
            scheduledIncomes[idx].copyWith(status: ScheduledStatus.expected, clearTransaction: true);
      }
    }
    if (t.debtId != null) _refreshDebtStatus(t.debtId!);
    _audit('Movimiento eliminado', '${t.type.label} · ${t.description}: ${formatMoney(t.amount)}');
  }

  List<Transaction> get transactionsSorted {
    final list = [...transactions];
    list.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  // -------------------------------------------------------------------------
  // Deudas
  // -------------------------------------------------------------------------

  Debt addDebt({
    required String name,
    required Cents total,
    required DateTime startDate,
    String description = '',
    List<({Cents amount, DateTime dueDate})> installments = const [],
  }) {
    final n = name.trim();
    if (n.isEmpty) throw FinanceException('La deuda necesita un nombre.');
    _requirePositive(total);
    for (final i in installments) {
      if (i.amount <= 0) throw FinanceException('Cada cuota debe tener un importe mayor que cero.');
    }
    final d = Debt(id: _id(), name: n, total: total, startDate: dayOf(startDate), description: description.trim());
    debts.add(d);
    final sorted = [...installments]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    for (var k = 0; k < sorted.length; k++) {
      this.installments.add(Installment(
          id: _id(), debtId: d.id, number: k + 1, amount: sorted[k].amount, dueDate: dayOf(sorted[k].dueDate)));
    }
    _audit('Deuda creada', '$n: ${formatMoney(total)} en ${sorted.length} cuotas');
    return d;
  }

  void updateDebt(String id, {String? name, Cents? total, DateTime? startDate, String? description}) {
    final d = debt(id);
    if (name != null && name.trim().isEmpty) throw FinanceException('La deuda necesita un nombre.');
    if (total != null) _requirePositive(total);
    debts[debts.indexOf(d)] = d.copyWith(
      name: name?.trim(),
      total: total,
      startDate: startDate == null ? null : dayOf(startDate),
      description: description?.trim(),
    );
    final changes = <String>[
      if (name != null && name.trim() != d.name) 'nombre: ${d.name} → ${name.trim()}',
      if (total != null && total != d.total) 'monto: ${formatMoney(d.total)} → ${formatMoney(total)}',
    ];
    _audit('Deuda editada', '${d.name}${changes.isEmpty ? '' : ' (${changes.join(', ')})'}');
  }

  void cancelDebt(String id) {
    final d = debt(id);
    debts[debts.indexOf(d)] = d.copyWith(status: DebtStatus.cancelled);
    _audit('Deuda cancelada', d.name);
  }

  void reactivateDebt(String id) {
    final d = debt(id);
    debts[debts.indexOf(d)] = d.copyWith(status: DebtStatus.active);
    _refreshDebtStatus(id);
    _audit('Deuda reactivada', d.name);
  }

  /// Elimina una deuda solo si no tiene pagos registrados.
  void deleteDebt(String id) {
    final d = debt(id);
    if (transactions.any((t) => t.debtId == id)) {
      throw FinanceException('La deuda tiene pagos registrados. Cancélala en lugar de eliminarla.');
    }
    debts.remove(d);
    installments.removeWhere((i) => i.debtId == id);
    _audit('Deuda eliminada', d.name);
  }

  List<Installment> installmentsOf(String debtId) =>
      installments.where((i) => i.debtId == debtId).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  void _renumber(String debtId) {
    final list = installmentsOf(debtId);
    for (var k = 0; k < list.length; k++) {
      final idx = installments.indexOf(list[k]);
      installments[idx] = list[k].copyWith(number: k + 1);
    }
  }

  Installment addInstallment(String debtId, {required Cents amount, required DateTime dueDate}) {
    final d = debt(debtId);
    _requirePositive(amount);
    final inst = Installment(id: _id(), debtId: debtId, number: 0, amount: amount, dueDate: dayOf(dueDate));
    installments.add(inst);
    _renumber(debtId);
    _refreshDebtStatus(debtId);
    _audit('Cuota agregada', '${d.name}: ${formatMoney(amount)} el ${_fmtDate(dueDate)}');
    return installment(inst.id);
  }

  /// Edición controlada: registra importe/fecha anterior y nuevo.
  void updateInstallment(String id, {Cents? amount, DateTime? dueDate}) {
    final inst = installment(id);
    if (amount != null) {
      _requirePositive(amount);
      final paid = paidForInstallment(id);
      if (amount < paid) {
        throw FinanceException('El nuevo importe (${formatMoney(amount)}) es menor que lo ya abonado (${formatMoney(paid)}).');
      }
    }
    final updated = inst.copyWith(amount: amount, dueDate: dueDate == null ? null : dayOf(dueDate));
    installments[installments.indexOf(inst)] = updated;
    _renumber(inst.debtId);
    _refreshDebtStatus(inst.debtId);
    final changes = <String>[
      if (amount != null && amount != inst.amount) 'importe ${formatMoney(inst.amount)} → ${formatMoney(amount)}',
      if (dueDate != null && dayOf(dueDate) != inst.dueDate) 'fecha ${_fmtDate(inst.dueDate)} → ${_fmtDate(dueDate)}',
    ];
    _audit('Cuota editada', '${debt(inst.debtId).name} #${inst.number}: ${changes.isEmpty ? 'sin cambios' : changes.join(', ')}');
  }

  void setInstallmentCancelled(String id, bool cancelled) {
    final inst = installment(id);
    if (cancelled && paidForInstallment(id) > 0) {
      throw FinanceException('La cuota tiene abonos registrados; elimina primero esos movimientos.');
    }
    installments[installments.indexOf(inst)] = inst.copyWith(cancelled: cancelled);
    _refreshDebtStatus(inst.debtId);
    _audit(cancelled ? 'Cuota cancelada' : 'Cuota restaurada', '${debt(inst.debtId).name} #${inst.number}');
  }

  void deleteInstallment(String id) {
    final inst = installment(id);
    if (paidForInstallment(id) > 0) {
      throw FinanceException('La cuota tiene abonos registrados; no se puede eliminar.');
    }
    installments.remove(inst);
    _renumber(inst.debtId);
    _refreshDebtStatus(inst.debtId);
    _audit('Cuota eliminada', '${debt(inst.debtId).name}: ${formatMoney(inst.amount)} del ${_fmtDate(inst.dueDate)}');
  }

  List<Transaction> paymentsForInstallment(String installmentId) =>
      transactions.where((t) => t.type == TxType.debtPayment && t.installmentId == installmentId).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  Cents paidForInstallment(String installmentId) =>
      paymentsForInstallment(installmentId).fold<int>(0, (s, t) => s + t.amount);

  Cents remainingForInstallment(String installmentId) {
    final inst = installment(installmentId);
    if (inst.cancelled) return 0;
    final r = inst.amount - paidForInstallment(installmentId);
    return r < 0 ? 0 : r;
  }

  InstallmentStatus installmentStatus(Installment inst) {
    if (inst.cancelled) return InstallmentStatus.cancelled;
    final paid = paidForInstallment(inst.id);
    if (paid >= inst.amount) return InstallmentStatus.paid;
    if (inst.dueDate.isBefore(today)) return InstallmentStatus.overdue;
    if (paid > 0) return InstallmentStatus.partial;
    return InstallmentStatus.pending;
  }

  bool isInstallmentOpen(Installment inst) {
    final s = installmentStatus(inst);
    return s != InstallmentStatus.paid && s != InstallmentStatus.cancelled;
  }

  /// Registra el pago (total o abono parcial) de una cuota.
  ///
  /// - Descuenta el importe de la cuenta elegida, una sola vez.
  /// - Rechaza pagar una cuota ya pagada o cancelada.
  /// - Rechaza importes mayores a lo que falta de la cuota.
  Transaction payInstallment({
    required String installmentId,
    required String accountId,
    DateTime? date,
    Cents? amount,
  }) {
    final inst = installment(installmentId);
    final d = debt(inst.debtId);
    account(accountId);
    if (d.status == DebtStatus.cancelled) throw FinanceException('La deuda está cancelada.');
    if (inst.cancelled) throw FinanceException('La cuota está cancelada.');
    final remaining = remainingForInstallment(installmentId);
    if (remaining == 0) throw FinanceException('Esta cuota ya está pagada; no se vuelve a descontar.');
    final pay = amount ?? remaining;
    _requirePositive(pay);
    if (pay > remaining) {
      throw FinanceException('El abono (${formatMoney(pay)}) supera lo que falta de la cuota (${formatMoney(remaining)}).');
    }
    final t = _addTx(Transaction(
      id: _id(),
      date: dayOf(date ?? clock()),
      amount: pay,
      type: TxType.debtPayment,
      description: 'Pago ${d.name} · cuota ${inst.number}',
      accountId: accountId,
      category: 'Deudas',
      debtId: d.id,
      installmentId: inst.id,
      createdAt: clock(),
    ));
    _refreshDebtStatus(d.id);
    _audit(pay == remaining ? 'Cuota pagada' : 'Abono a cuota',
        '${d.name} #${inst.number}: ${formatMoney(pay)} desde ${account(accountId).name}');
    return t;
  }

  /// Marca la deuda como liquidada cuando todas sus cuotas están pagadas,
  /// y la reactiva si deja de estarlo (por ejemplo, al borrar un pago).
  void _refreshDebtStatus(String debtId) {
    final idx = debts.indexWhere((d) => d.id == debtId);
    if (idx < 0) return;
    final d = debts[idx];
    if (d.status == DebtStatus.cancelled) return;
    final insts = installmentsOf(debtId).where((i) => !i.cancelled).toList();
    final allPaid = insts.isNotEmpty && insts.every((i) => paidForInstallment(i.id) >= i.amount);
    final next = allPaid ? DebtStatus.settled : DebtStatus.active;
    if (next != d.status) debts[idx] = d.copyWith(status: next);
  }

  DebtSummary summaryOf(String debtId) {
    final d = debt(debtId);
    final insts = installmentsOf(debtId);
    final paid = transactions.where((t) => t.type == TxType.debtPayment && t.debtId == debtId).fold<int>(0, (s, t) => s + t.amount);
    final pending = insts.where((i) => !i.cancelled).fold<int>(0, (s, i) => s + remainingForInstallment(i.id));
    return DebtSummary(debt: d, installments: insts, paid: paid, pendingInstallments: pending);
  }

  /// Total pendiente de todas las deudas activas (monto original - pagado).
  Cents get totalPendingDebt => debts
      .where((d) => d.status == DebtStatus.active)
      .fold<int>(0, (s, d) => s + (summaryOf(d.id).remaining > 0 ? summaryOf(d.id).remaining : 0));

  /// Cuotas abiertas (no pagadas ni canceladas) de deudas activas, por fecha.
  List<Installment> get openInstallments {
    final activeDebts = debts.where((d) => d.status == DebtStatus.active).map((d) => d.id).toSet();
    return installments.where((i) => activeDebts.contains(i.debtId) && isInstallmentOpen(i)).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  List<Installment> get overdueInstallments =>
      openInstallments.where((i) => i.dueDate.isBefore(today)).toList();

  Installment? get nextPayment {
    final upcoming = openInstallments.where((i) => !i.dueDate.isBefore(today));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// Lo que falta pagar de las cuotas que vencen en el mes de [month].
  Cents pendingPaymentsInMonth(DateTime month) => openInstallments
      .where((i) => i.dueDate.year == month.year && i.dueDate.month == month.month)
      .fold<int>(0, (s, i) => s + remainingForInstallment(i.id));

  /// Importe total de cuotas (pagadas o no) que vencen en el mes de [month].
  Cents scheduledPaymentsInMonth(DateTime month) => installments
      .where((i) => !i.cancelled && i.dueDate.year == month.year && i.dueDate.month == month.month)
      .where((i) {
    final d = debts.where((x) => x.id == i.debtId);
    return d.isNotEmpty && d.first.status != DebtStatus.cancelled;
  }).fold<int>(0, (s, i) => s + i.amount);

  // -------------------------------------------------------------------------
  // Ingresos previstos
  // -------------------------------------------------------------------------

  ScheduledIncome addScheduledIncome({
    required String accountId,
    required Cents amount,
    required DateTime date,
    String description = 'Ingreso previsto',
  }) {
    _requirePositive(amount);
    account(accountId);
    final s = ScheduledIncome(
      id: _id(),
      date: dayOf(date),
      amount: amount,
      description: description.trim().isEmpty ? 'Ingreso previsto' : description.trim(),
      accountId: accountId,
    );
    scheduledIncomes.add(s);
    _audit('Ingreso previsto', '${s.description}: ${formatMoney(amount)} el ${_fmtDate(date)}');
    return s;
  }

  /// Confirma que el dinero llegó: solo entonces aumenta el saldo real.
  Transaction confirmScheduledIncome(String id, {Cents? actualAmount, DateTime? date, String? accountId}) {
    final s = scheduledIncome(id);
    if (s.status == ScheduledStatus.received) throw FinanceException('Este ingreso ya fue confirmado.');
    final amount = actualAmount ?? s.amount;
    _requirePositive(amount);
    final acc = accountId ?? s.accountId;
    account(acc);
    final t = _addTx(Transaction(
      id: _id(),
      date: dayOf(date ?? clock()),
      amount: amount,
      type: TxType.income,
      description: s.description,
      accountId: acc,
      scheduledItemId: s.id,
      createdAt: clock(),
    ));
    scheduledIncomes[scheduledIncomes.indexOf(s)] = s.copyWith(status: ScheduledStatus.received, transactionId: t.id);
    _audit('Ingreso recibido', '${s.description}: ${formatMoney(amount)}');
    return t;
  }

  void markScheduledIncomeNotReceived(String id) {
    final s = scheduledIncome(id);
    if (s.status == ScheduledStatus.received) {
      throw FinanceException('Ya fue recibido; elimina el movimiento si fue un error.');
    }
    scheduledIncomes[scheduledIncomes.indexOf(s)] = s.copyWith(status: ScheduledStatus.notReceived);
    _audit('Ingreso no recibido', s.description);
  }

  void deleteScheduledIncome(String id) {
    final s = scheduledIncome(id);
    if (s.status == ScheduledStatus.received) {
      throw FinanceException('Ya fue recibido; elimina el movimiento correspondiente primero.');
    }
    scheduledIncomes.remove(s);
    _audit('Ingreso previsto eliminado', s.description);
  }

  List<ScheduledIncome> get expectedIncomes =>
      scheduledIncomes.where((s) => s.status == ScheduledStatus.expected).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  ScheduledIncome? get nextIncome {
    final list = expectedIncomes.where((s) => !s.date.isBefore(today));
    return list.isEmpty ? null : list.first;
  }

  // -------------------------------------------------------------------------
  // Resúmenes y agenda
  // -------------------------------------------------------------------------

  /// Ingresos y gastos reales del mes. Transferencias y ajustes no cuentan.
  MonthSummary monthSummary(DateTime month) {
    var inc = 0, exp = 0, debt = 0;
    for (final t in transactions) {
      if (t.date.year != month.year || t.date.month != month.month) continue;
      switch (t.type) {
        case TxType.income:
          inc += t.amount;
        case TxType.expense:
          exp += t.amount;
        case TxType.debtPayment:
          debt += t.amount;
        case TxType.transfer:
        case TxType.adjustment:
          break;
      }
    }
    return MonthSummary(inc, exp, debt);
  }

  /// Agenda de próximos eventos: cuotas abiertas e ingresos previstos.
  /// Cada evento está vinculado a su cuota/ingreso original (sin duplicados).
  List<AgendaItem> agenda({int days = 60}) {
    final limit = today.add(Duration(days: days));
    final items = <AgendaItem>[
      for (final i in openInstallments)
        if (!i.dueDate.isAfter(limit))
          AgendaItem(
            date: i.dueDate,
            title: '${debt(i.debtId).name} · cuota ${i.number}',
            amount: remainingForInstallment(i.id),
            isIncome: false,
            statusLabel: installmentStatus(i).label,
            installmentId: i.id,
          ),
      for (final s in expectedIncomes)
        if (!s.date.isAfter(limit))
          AgendaItem(
            date: s.date,
            title: s.description,
            amount: s.amount,
            isIncome: true,
            statusLabel: s.date.isBefore(today) ? 'Previsto (atrasado)' : 'Previsto',
            scheduledIncomeId: s.id,
          ),
    ];
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  /// Alertas importantes para la pantalla de inicio.
  List<String> get alerts {
    final out = <String>[];
    final overdue = overdueInstallments;
    if (overdue.isNotEmpty) {
      final sum = overdue.fold<int>(0, (s, i) => s + remainingForInstallment(i.id));
      out.add('Tienes ${overdue.length} cuota(s) vencida(s) por ${formatMoney(sum)}.');
    }
    final weekLimit = today.add(const Duration(days: 7));
    final week = openInstallments.where((i) => !i.dueDate.isBefore(today) && !i.dueDate.isAfter(weekLimit)).toList();
    if (week.isNotEmpty) {
      final sum = week.fold<int>(0, (s, i) => s + remainingForInstallment(i.id));
      out.add('Pagos en los próximos 7 días: ${formatMoney(sum)}.');
      final needed = sum + overdue.fold<int>(0, (s, i) => s + remainingForInstallment(i.id));
      if (needed > totalAvailable) {
        out.add('Saldo insuficiente: necesitas ${formatMoney(needed)} y tienes ${formatMoney(totalAvailable)} disponible.');
      }
    }
    for (final d in debts.where((d) => d.status == DebtStatus.active)) {
      final s = summaryOf(d.id);
      if (s.hasMismatch) {
        out.add('${d.name}: el saldo pendiente (${formatMoney(s.remaining)}) no coincide con la suma de cuotas (${formatMoney(s.pendingInstallments)}).');
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Serialización (persistencia y respaldo)
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'debts': debts.map((e) => e.toJson()).toList(),
        'installments': installments.map((e) => e.toJson()).toList(),
        'scheduledIncomes': scheduledIncomes.map((e) => e.toJson()).toList(),
        'auditLog': auditLog.map((e) => e.toJson()).toList(),
      };

  factory Ledger.fromJson(Map<String, dynamic> j, {DateTime Function()? clock}) {
    final v = j['schemaVersion'];
    if (v is! int || v > schemaVersion) {
      throw FinanceException('Formato de datos no compatible (versión $v).');
    }
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    final l = Ledger(
      accounts: list('accounts', Account.fromJson),
      transactions: list('transactions', Transaction.fromJson),
      debts: list('debts', Debt.fromJson),
      installments: list('installments', Installment.fromJson),
      scheduledIncomes: list('scheduledIncomes', ScheduledIncome.fromJson),
      auditLog: list('auditLog', AuditEntry.fromJson),
      clock: clock,
    );
    l._validateIntegrity();
    return l;
  }

  /// Verifica claves foráneas básicas al cargar datos (por ejemplo, un respaldo).
  void _validateIntegrity() {
    final accIds = accounts.map((a) => a.id).toSet();
    final debtIds = debts.map((d) => d.id).toSet();
    final instIds = installments.map((i) => i.id).toSet();
    for (final t in transactions) {
      if (!accIds.contains(t.accountId) || (t.toAccountId != null && !accIds.contains(t.toAccountId))) {
        throw FinanceException('Datos dañados: movimiento con cuenta inexistente.');
      }
      if ((t.debtId != null && !debtIds.contains(t.debtId)) ||
          (t.installmentId != null && !instIds.contains(t.installmentId))) {
        throw FinanceException('Datos dañados: pago vinculado a una deuda o cuota inexistente.');
      }
    }
    for (final i in installments) {
      if (!debtIds.contains(i.debtId)) throw FinanceException('Datos dañados: cuota sin deuda.');
    }
  }

  Ledger clone() => Ledger.fromJson(toJson(), clock: clock);
}

String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
