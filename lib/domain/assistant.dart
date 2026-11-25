import 'package:intl/intl.dart';

import 'ledger.dart';
import 'models.dart';
import 'money.dart';
import 'scenarios.dart';

/// Asistente por reglas (sin IA): interpreta instrucciones en español y
/// propone operaciones del motor financiero. NUNCA modifica datos por sí
/// mismo: devuelve propuestas que el usuario confirma.
sealed class AssistantReply {
  const AssistantReply();
}

/// Respuesta informativa (consultas).
class AnswerReply extends AssistantReply {
  final String text;
  const AnswerReply(this.text);
}

/// Operación propuesta: se ejecuta solo si el usuario confirma.
class ProposalReply extends AssistantReply {
  final String title;
  final List<String> details;
  final void Function(Ledger l) apply;

  /// Texto a mostrar después de aplicar (recibe el libro ya actualizado).
  final String Function(Ledger l) done;
  const ProposalReply({required this.title, required this.details, required this.apply, required this.done});
}

/// Hay varias posibilidades: el usuario elige una.
class ChoiceReply extends AssistantReply {
  final String question;
  final List<(String, AssistantReply)> options;
  const ChoiceReply(this.question, this.options);
}

/// Resultado de una simulación (no guardada).
class SimulationReply extends AssistantReply {
  final String text;
  final Scenario scenario;
  const SimulationReply(this.text, this.scenario);
}

/// «Cancela esa simulación».
class CancelSimulationReply extends AssistantReply {
  const CancelSimulationReply();
}

// ---------------------------------------------------------------------------
// Utilidades de texto
// ---------------------------------------------------------------------------

String normalize(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r'[¿?¡!]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _has(String t, List<String> words) => words.any((w) => RegExp('(^|[^a-z])$w').hasMatch(t));

const _months = {
  'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5, 'junio': 6, 'julio': 7, 'agosto': 8,
  'septiembre': 9, 'setiembre': 9, 'octubre': 10, 'noviembre': 11, 'diciembre': 12,
};

/// Extrae una fecha («hoy», «ayer», «el 20 de noviembre», «20/11») y
/// devuelve el texto sin ella (para no confundir el día con un importe).
(DateTime?, String) _extractDate(String t, DateTime today) {
  final m1 = RegExp(r'(el )?(\d{1,2}) de (' + _months.keys.join('|') + r')( de (\d{4}))?').firstMatch(t);
  if (m1 != null) {
    final month = _months[m1.group(3)]!;
    var year = int.tryParse(m1.group(5) ?? '') ?? today.year;
    final d = DateTime(year, month, int.parse(m1.group(2)!));
    return (d, t.replaceRange(m1.start, m1.end, ' '));
  }
  final m2 = RegExp(r'(el )?(\d{1,2})/(\d{1,2})(/(\d{2,4}))?').firstMatch(t);
  if (m2 != null) {
    var year = int.tryParse(m2.group(5) ?? '') ?? today.year;
    if (year < 100) year += 2000;
    return (DateTime(year, int.parse(m2.group(3)!), int.parse(m2.group(2)!)), t.replaceRange(m2.start, m2.end, ' '));
  }
  for (final (w, delta) in [('antier', -2), ('anteayer', -2), ('ayer', -1), ('hoy', 0), ('manana', 1), ('pasado manana', 2)]) {
    if (RegExp('(^| )$w( |\$)').hasMatch(t)) {
      return (today.add(Duration(days: delta)), t.replaceAll(RegExp('(^| )$w( |\$)'), ' '));
    }
  }
  return (null, t);
}

/// Mes mencionado: «diciembre», «este mes», «el proximo mes».
DateTime? _extractMonth(String t, DateTime today) {
  if (t.contains('este mes')) return DateTime(today.year, today.month);
  if (t.contains('proximo mes') || t.contains('siguiente mes') || t.contains('mes que viene')) {
    return DateTime(today.year, today.month + 1);
  }
  if (t.contains('mes pasado')) return DateTime(today.year, today.month - 1);
  for (final e in _months.entries) {
    if (RegExp('(^| )${e.key}( |\$)').hasMatch(t)) {
      // El mes más cercano hacia adelante (o el actual).
      var y = today.year;
      if (e.value < today.month - 6) y++;
      return DateTime(y, e.value);
    }
  }
  return null;
}

/// Importes: «500», «$1,200.50», «1200 pesos», «2 mil».
List<Cents> _amounts(String t) {
  final out = <Cents>[];
  final re = RegExp(r'\$?\s?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(\s?mil\b)?');
  for (final m in re.allMatches(t)) {
    final whole = int.parse(m.group(1)!.replaceAll(',', ''));
    final frac = (m.group(2) ?? '').padRight(2, '0');
    var cents = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
    if (m.group(3) != null) cents *= 1000;
    out.add(cents);
  }
  return out;
}

const _categoryWords = {
  'Comida': ['comida', 'taco', 'super', 'despensa', 'restaurante', 'almuerzo', 'comer', 'cena', 'desayuno', 'tortilla', 'pan'],
  'Transporte': ['transporte', 'gasolina', 'camion', 'taxi', 'metro', 'pasaje', 'uber', 'combi', 'estacionamiento'],
  'Servicios': ['luz', 'agua', 'internet', 'telefono', 'recarga', 'gas', 'servicio'],
  'Salud': ['farmacia', 'medico', 'doctor', 'medicina', 'consulta', 'dentista'],
  'Entretenimiento': ['cine', 'netflix', 'spotify', 'juego', 'fiesta', 'salida'],
  'Compras': ['ropa', 'zapato', 'amazon', 'mercado libre', 'tienda', 'compra'],
  'Hogar': ['renta', 'casa', 'mueble', 'limpieza'],
};

String? _category(String t) {
  for (final e in _categoryWords.entries) {
    if (e.value.any((w) => t.contains(w))) return e.key;
  }
  return null;
}

final _date = DateFormat("d 'de' MMMM", 'es_MX');
String _fd(DateTime d) => _date.format(d);

bool _mentionsDigital(String t) => _has(t, ['digital', 'banco', 'tarjeta', 'cuenta', 'transferencia', 'deposit', 'mercado pago', 'nu ', 'bbva']);

Account _accountFor(Ledger l, String t, {bool? digital}) {
  final active = l.activeAccounts;
  // Por nombre de cuenta (si el usuario la menciona).
  for (final a in active) {
    final n = normalize(a.name);
    if (n.length >= 3 && t.contains(n)) return a;
  }
  final wantDigital = digital ?? _mentionsDigital(t);
  final kind = wantDigital ? AccountKind.digital : AccountKind.physical;
  return active.firstWhere((a) => a.kind == kind, orElse: () => active.first);
}

/// Deudas mencionadas por nombre (por palabras de al menos 3 letras).
List<Debt> _debtsIn(Ledger l, String t) {
  final out = <Debt>[];
  for (final d in l.debts.where((d) => d.status == DebtStatus.active)) {
    final words = normalize(d.name).split(' ').where((w) => w.length >= 3 && !const {'prestamos', 'prestamo', 'pago', 'pagos'}.contains(w));
    if (words.any((w) => RegExp('(^|[^a-z])$w').hasMatch(t))) out.add(d);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Intérprete
// ---------------------------------------------------------------------------

const helpText = 'Puedo ayudarte con cosas como:\n'
    '• «Tengo 500» · «Digital tengo 150» (corregir saldos)\n'
    '• «Hoy gasté 80 en comida» · «Pagué 120 de luz con tarjeta»\n'
    '• «Recibí 400» · «Ya recibí el ingreso semanal»\n'
    '• «Pagué DiDi» · «Pagué los 750 de DiDi» · «Abono 300 a Coppel»\n'
    '• «Cambió la cuota de Coppel a 450»\n'
    '• «Pasé 200 al banco» · «Saqué 100 del banco»\n'
    '• «¿Cuánto debo en diciembre?» · «¿Cuánto tengo?» · «¿Cuál es mi próximo pago?»\n'
    '• «¿Cuánto gasté este mes?» · «¿Cuánto tenía el 20 de noviembre?»\n'
    '• «Simula diciembre con 400 semanales» · «Simula una semana sin ingresos» · «Cancela esa simulación»\n'
    'Antes de cambiar cualquier dato te pido confirmación.';

AssistantReply interpret(String input, Ledger l) {
  final today = l.today;
  final raw = normalize(input);
  if (raw.isEmpty || _has(raw, ['ayuda', 'que puedes', 'como funciona', 'hola'])) return const AnswerReply(helpText);

  final (date, t) = _extractDate(raw, today);
  final amounts = _amounts(t);
  final amount = amounts.isEmpty ? null : amounts.first;

  if (raw.contains('simulacion') && _has(raw, ['cancela', 'borra', 'descarta', 'olvida', 'quita'])) {
    return const CancelSimulationReply();
  }
  if (_has(raw, ['simula', 'que pasa si', 'que pasaria si', 'y si '])) return _simulate(l, raw, t, amount, date);

  final isQuestion = input.contains('?') || _has(raw, ['cuanto', 'cuando', 'cual', 'cuales', 'que pagos', 'dime', 'muestra']);
  if (isQuestion && !_has(raw, ['cambio', 'cambia'])) return _query(l, raw, t, date);

  if (_has(raw, ['cambio', 'cambia', 'ahora es', 'subio', 'bajo']) && raw.contains('cuota')) return _changeInstallment(l, raw, amount, date);

  if (_has(raw, ['transferi', 'pase', 'deposite', 'meti', 'mande']) && amount != null && _mentionsDigital(raw)) {
    return _transfer(l, toDigital: true, amount: amount, date: date ?? today);
  }
  if (_has(raw, ['retire', 'saque']) && amount != null) return _transfer(l, toDigital: false, amount: amount, date: date ?? today);

  if (_has(raw, ['recibi', 'me pagaron', 'me depositaron', 'cobre', 'llego', 'me dieron', 'me llego', 'gane'])) {
    return _income(l, raw, amount, date ?? today);
  }

  final debts = _debtsIn(l, raw);
  if (_has(raw, ['pague', 'abone', 'abono', 'liquide', 'pago']) && debts.isNotEmpty) {
    return _payDebt(l, raw, debts, amount, date ?? today);
  }

  if (_has(raw, ['tengo', 'traigo', 'me quedan', 'me queda', 'hay']) && amount != null && !_has(raw, ['debo', 'pagar'])) {
    return _setBalance(l, raw, amount);
  }

  if (_has(raw, ['gaste', 'compre', 'pague', 'pago', 'gasto', 'gasté']) && amount != null) {
    // ¿Es un gasto programado (ej. «pagué internet»)?
    final scheduled = l.agenda(days: 15).where((e) => e.kind == EventKind.expense && e.isOpen && raw.contains(normalize(e.title)));
    if (scheduled.isNotEmpty) return _confirmScheduled(l, scheduled.first, amount, date ?? today, raw);
    return _expense(l, raw, t, amount, date ?? today);
  }
  if (_has(raw, ['pague', 'pago'])) {
    final scheduled = l.agenda(days: 15).where((e) => e.kind == EventKind.expense && e.isOpen && raw.contains(normalize(e.title)));
    if (scheduled.isNotEmpty) return _confirmScheduled(l, scheduled.first, scheduled.first.amount, date ?? today, raw);
  }

  return const AnswerReply('No entendí esa instrucción. Escribe «ayuda» para ver ejemplos de lo que puedo hacer.');
}

// --- Saldos ----------------------------------------------------------------

AssistantReply _setBalance(Ledger l, String t, Cents amount) {
  final acc = _accountFor(l, t);
  final current = l.balance(acc.id);
  if (current == amount) return AnswerReply('${acc.name} ya tiene ${formatMoney(amount)}. No hay nada que corregir.');
  return ProposalReply(
    title: 'Corregir saldo de ${acc.name}',
    details: [
      '${acc.kind.label}: ${formatMoney(current)} → ${formatMoney(amount)}',
      'Se registra un ajuste de ${formatMoney(amount - current, signed: true)}.',
    ],
    apply: (l) => l.setBalance(accountId: acc.id, newBalance: amount, note: 'Corrección desde el asistente'),
    done: (l) => 'Listo. ${acc.kind.label}: ${formatMoney(l.totalByKind(acc.kind))}. Total disponible: ${formatMoney(l.totalAvailable)}.',
  );
}

// --- Gastos ----------------------------------------------------------------

AssistantReply _expense(Ledger l, String raw, String t, Cents amount, DateTime date) {
  final acc = _accountFor(l, raw);
  final cat = _category(raw);
  var desc = cat ?? 'Gasto';
  final m = RegExp(r'\b(?:en|de|para) (?:la |el |los |las |un |una )?([a-z ]{3,30}?)(?: con | desde | en efectivo|$)').firstMatch(t.replaceAll(RegExp(r'\d+|pesos|\$'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim());
  if (m != null) {
    final word = m.group(1)!.trim();
    if (word.isNotEmpty && !const {'efectivo', 'tarjeta', 'banco', 'pesos'}.contains(word)) {
      desc = word[0].toUpperCase() + word.substring(1);
    }
  }
  return ProposalReply(
    title: 'Registrar gasto',
    details: [
      'Importe: ${formatMoney(amount)}',
      'Cuenta: ${acc.name}',
      'Categoría: ${cat ?? 'Otros'}',
      'Descripción: $desc',
      'Fecha: ${_fd(date)}',
    ],
    apply: (l) => l.addExpense(accountId: acc.id, amount: amount, date: date, description: desc, category: cat ?? 'Otros'),
    done: (l) => 'Gasto registrado. Nuevo saldo de ${acc.name}: ${formatMoney(l.balance(acc.id))}.',
  );
}

AssistantReply _confirmScheduled(Ledger l, CalendarEvent e, Cents amount, DateTime date, String raw) {
  final acc = _accountFor(l, raw, digital: _mentionsDigital(raw) ? true : null);
  return ProposalReply(
    title: 'Confirmar pago de «${e.title}»',
    details: ['Previsto para el ${_fd(e.date)}: ${formatMoney(e.amount)}', 'Pagado: ${formatMoney(amount)} desde ${acc.name}'],
    apply: (l) => l.confirmScheduledItem(
      l.ensureScheduledItem(scheduledItemId: e.scheduledItemId, recurrenceId: e.recurrenceId, occurrenceDate: e.occurrenceDate),
      actualAmount: amount,
      date: date,
      accountId: acc.id,
    ),
    done: (l) => 'Pago registrado. Saldo de ${acc.name}: ${formatMoney(l.balance(acc.id))}.',
  );
}

// --- Ingresos --------------------------------------------------------------

AssistantReply _income(Ledger l, String raw, Cents? amount, DateTime date) {
  // ¿Corresponde a un ingreso previsto? (de 7 días antes a 3 después)
  final candidates = l
      .eventsBetween(date.subtract(const Duration(days: 7)), date.add(const Duration(days: 3)))
      .where((e) => e.isIncome && e.isOpen)
      .where((e) => amount == null || e.amount == amount || raw.contains(normalize(e.title)))
      .toList();

  ProposalReply confirmExpected(CalendarEvent e) {
    final received = amount ?? e.amount;
    final acc = _mentionsDigital(raw) ? _accountFor(l, raw) : null;
    return ProposalReply(
      title: 'Confirmar ingreso «${e.title}»',
      details: [
        'Previsto: ${formatMoney(e.amount)} el ${_fd(e.date)}',
        'Recibido: ${formatMoney(received)}${acc == null ? '' : ' en ${acc.name}'}',
        'Pasará de «previsto» a «recibido» y se sumará a tu saldo.',
      ],
      apply: (l) => l.confirmScheduledItem(
        l.ensureScheduledItem(scheduledItemId: e.scheduledItemId, recurrenceId: e.recurrenceId, occurrenceDate: e.occurrenceDate),
        actualAmount: received,
        date: date,
        accountId: acc?.id,
      ),
      done: (l) => 'Ingreso confirmado. Total disponible: ${formatMoney(l.totalAvailable)}.',
    );
  }

  if (candidates.length == 1) return confirmExpected(candidates.single);
  if (candidates.length > 1) {
    return ChoiceReply('¿A cuál ingreso previsto corresponde?', [
      for (final e in candidates.take(4)) ('${e.title} · ${_fd(e.date)} · ${formatMoney(e.amount)}', confirmExpected(e)),
      if (amount != null) ('Es otro ingreso', _newIncome(l, raw, amount, date)),
    ]);
  }
  if (amount == null) return const AnswerReply('¿Cuánto recibiste? Por ejemplo: «Recibí 400».');
  return _newIncome(l, raw, amount, date);
}

ProposalReply _newIncome(Ledger l, String raw, Cents amount, DateTime date) {
  final acc = _accountFor(l, raw);
  return ProposalReply(
    title: 'Registrar ingreso recibido',
    details: ['Importe: +${formatMoney(amount)}', 'Cuenta: ${acc.name}', 'Fecha: ${_fd(date)}'],
    apply: (l) => l.addIncome(accountId: acc.id, amount: amount, date: date, description: 'Ingreso'),
    done: (l) => 'Ingreso registrado. Nuevo saldo de ${acc.name}: ${formatMoney(l.balance(acc.id))}.',
  );
}

// --- Transferencias --------------------------------------------------------

AssistantReply _transfer(Ledger l, {required bool toDigital, required Cents amount, required DateTime date}) {
  final cash = l.activeAccounts.firstWhere((a) => a.kind == AccountKind.physical, orElse: () => l.activeAccounts.first);
  final bank = l.activeAccounts.firstWhere((a) => a.kind == AccountKind.digital, orElse: () => l.activeAccounts.last);
  final from = toDigital ? cash : bank;
  final to = toDigital ? bank : cash;
  return ProposalReply(
    title: 'Transferencia entre tus cuentas',
    details: ['${from.name} → ${to.name}: ${formatMoney(amount)}', 'No cuenta como ingreso ni gasto: tu total no cambia.'],
    apply: (l) => l.transfer(fromAccountId: from.id, toAccountId: to.id, amount: amount, date: date),
    done: (l) => 'Listo. ${from.name}: ${formatMoney(l.balance(from.id))} · ${to.name}: ${formatMoney(l.balance(to.id))}.',
  );
}

// --- Deudas ----------------------------------------------------------------

AssistantReply _payDebt(Ledger l, String raw, List<Debt> debts, Cents? amount, DateTime date) {
  if (debts.length > 1) {
    return ChoiceReply('¿Cuál deuda pagaste?', [
      for (final d in debts) (d.name, _payDebt(l, raw, [d], amount, date)),
    ]);
  }
  final d = debts.single;
  final open = l.installmentsOf(d.id).where(l.isInstallmentOpen).toList();
  if (open.isEmpty) return AnswerReply('${d.name} no tiene cuotas pendientes: no hay nada que descontar.');
  final acc = _accountFor(l, raw);

  ProposalReply pay(Installment i, Cents value) {
    final remaining = l.remainingForInstallment(i.id);
    final partial = value < remaining;
    return ProposalReply(
      title: partial ? 'Abono a ${d.name} · cuota ${i.number}' : 'Pagar ${d.name} · cuota ${i.number}',
      details: [
        'Cuota de ${formatMoney(i.amount)} que vence el ${_fd(i.dueDate)}',
        partial ? 'Abono: ${formatMoney(value)} (faltarán ${formatMoney(remaining - value)})' : 'Pago: ${formatMoney(value)}',
        'Desde: ${acc.name} · fecha ${_fd(date)}',
      ],
      apply: (l) => l.payInstallment(installmentId: i.id, accountId: acc.id, date: date, amount: value),
      done: (l) => '${partial ? 'Abono registrado' : 'Cuota pagada'}. ${d.name}: pendiente ${formatMoney(l.summaryOf(d.id).remaining)}. '
          'Saldo de ${acc.name}: ${formatMoney(l.balance(acc.id))}.',
    );
  }

  if (amount != null) {
    final exact = open.where((i) => l.remainingForInstallment(i.id) == amount).toList();
    if (exact.length == 1) return pay(exact.single, amount);
    final fits = open.where((i) => l.remainingForInstallment(i.id) >= amount).toList();
    if (fits.isEmpty) {
      return AnswerReply('${formatMoney(amount)} es más de lo que falta en cualquier cuota de ${d.name}. '
          'La cuota más grande pendiente es de ${formatMoney(open.map((i) => l.remainingForInstallment(i.id)).reduce((a, b) => a > b ? a : b))}.');
    }
    if (fits.length == 1) return pay(fits.single, amount);
    return ChoiceReply('¿A qué cuota de ${d.name} corresponden los ${formatMoney(amount)}?', [
      for (final i in fits.take(4))
        ('Cuota ${i.number} · ${_fd(i.dueDate)} · falta ${formatMoney(l.remainingForInstallment(i.id))}', pay(i, amount)),
    ]);
  }
  if (open.length == 1) return pay(open.single, l.remainingForInstallment(open.single.id));
  return ChoiceReply('${d.name} tiene ${open.length} cuotas pendientes. ¿Cuál pagaste?', [
    for (final i in open.take(4))
      ('Cuota ${i.number} · ${_fd(i.dueDate)} · ${formatMoney(l.remainingForInstallment(i.id))}', pay(i, l.remainingForInstallment(i.id))),
  ]);
}

AssistantReply _changeInstallment(Ledger l, String raw, Cents? amount, DateTime? date) {
  if (amount == null && date == null) {
    return const AnswerReply('¿A cuánto cambió la cuota? Por ejemplo: «Cambió la cuota de Coppel a 450».');
  }
  var debts = _debtsIn(l, raw);
  final active = l.debts.where((d) => d.status == DebtStatus.active).toList();
  if (debts.isEmpty) {
    if (active.length == 1) {
      debts = active;
    } else if (active.isEmpty) {
      return const AnswerReply('No tienes deudas activas.');
    } else {
      return ChoiceReply('¿De cuál deuda cambió la cuota?', [
        for (final d in active) (d.name, _changeInstallment(l, '${normalize(d.name)} $raw', amount, date)),
      ]);
    }
  }
  if (debts.length > 1) {
    return ChoiceReply('¿De cuál deuda?', [for (final d in debts) (d.name, _changeInstallment(l, normalize(d.name), amount, date))]);
  }
  final d = debts.single;
  final open = l.installmentsOf(d.id).where(l.isInstallmentOpen).toList();
  if (open.isEmpty) return AnswerReply('${d.name} no tiene cuotas pendientes.');

  ProposalReply change(Installment i) => ProposalReply(
        title: 'Actualizar ${d.name} · cuota ${i.number}',
        details: [
          if (amount != null) 'Importe: ${formatMoney(i.amount)} → ${formatMoney(amount)}',
          if (date != null) 'Vencimiento: ${_fd(i.dueDate)} → ${_fd(date)}',
          'El calendario y los recordatorios se actualizan solos.',
        ],
        apply: (l) => l.updateInstallment(i.id, amount: amount, dueDate: date),
        done: (l) => 'Cuota actualizada. Suma de cuotas pendientes de ${d.name}: ${formatMoney(l.summaryOf(d.id).pendingInstallments)}.',
      );

  if (open.length == 1) return change(open.single);
  return ChoiceReply('¿Cuál cuota de ${d.name} cambió?', [
    for (final i in open.take(4)) ('Cuota ${i.number} · ${_fd(i.dueDate)} · ${formatMoney(i.amount)}', change(i)),
  ]);
}

// --- Consultas -------------------------------------------------------------

AssistantReply _query(Ledger l, String raw, String t, DateTime? date) {
  final month = _extractMonth(raw, l.today);
  final monthName = month == null ? null : DateFormat('MMMM', 'es_MX').format(month);

  if (_has(raw, ['debo', 'deuda', 'pagar', 'pagos', 'pago']) && !_has(raw, ['proximo', 'siguiente', 'cuando'])) {
    if (month != null) {
      final events = l
          .eventsBetween(DateTime(month.year, month.month, 1), DateTime(month.year, month.month + 1, 0))
          .where((e) => !e.isIncome && e.isOpen)
          .toList();
      if (events.isEmpty) return AnswerReply('No tienes pagos pendientes en $monthName.');
      final sum = events.fold<int>(0, (s, e) => s + e.amount);
      return AnswerReply('En $monthName debes pagar ${formatMoney(sum)}:\n'
          '${events.map((e) => '• ${_fd(e.date)}: ${e.title} — ${formatMoney(e.amount)}').join('\n')}');
    }
    final active = l.debts.where((d) => d.status == DebtStatus.active).toList();
    if (active.isEmpty) return const AnswerReply('No tienes deudas activas.');
    return AnswerReply('Debes en total ${formatMoney(l.totalPendingDebt)}:\n'
        '${active.map((d) => '• ${d.name}: ${formatMoney(l.summaryOf(d.id).remaining)}').join('\n')}');
  }

  if (_has(raw, ['proximo', 'siguiente', 'cuando']) && _has(raw, ['pago', 'pagar', 'vence', 'cuota'])) {
    final next = l.upcomingPayments(limit: 3);
    if (next.isEmpty) return const AnswerReply('No tienes pagos pendientes en los próximos 60 días.');
    return AnswerReply('Tus próximos pagos:\n${next.map((e) => '• ${_fd(e.date)}: ${e.title} — ${formatMoney(e.amount)}'
        '${e.overdue ? ' (vencido)' : ''}').join('\n')}');
  }

  if (_has(raw, ['gaste', 'gasto', 'gastos'])) {
    final m = month ?? DateTime(l.today.year, l.today.month);
    final s = l.monthSummary(m);
    final name = DateFormat('MMMM', 'es_MX').format(m);
    return AnswerReply('En $name gastaste ${formatMoney(s.expenses)} y pagaste ${formatMoney(s.debtPayments)} de deudas. '
        'Ingresos recibidos: ${formatMoney(s.income)}.');
  }

  if (_has(raw, ['recibi', 'ingresos', 'gane', 'ingreso'])) {
    final m = month ?? DateTime(l.today.year, l.today.month);
    final name = DateFormat('MMMM', 'es_MX').format(m);
    final expected = l
        .eventsBetween(l.today, DateTime(m.year, m.month + 1, 0))
        .where((e) => e.isIncome && e.isOpen)
        .fold<int>(0, (s, e) => s + e.amount);
    return AnswerReply('En $name has recibido ${formatMoney(l.monthSummary(m).income)}. '
        'Aún esperas ${formatMoney(expected)} en ingresos previstos (no cuentan como disponibles hasta que llegan).');
  }

  if (_has(raw, ['tengo', 'tenia', 'saldo', 'dinero', 'disponible'])) {
    if (date != null && date.isBefore(l.today)) {
      // Historial de saldos: cuánto había en una fecha.
      final phys = l.totalByKind(AccountKind.physical, asOf: date);
      final dig = l.totalByKind(AccountKind.digital, asOf: date);
      return AnswerReply('Al cierre del ${_fd(date)} tenías ${formatMoney(phys + dig)}: '
          '${formatMoney(phys)} en físico y ${formatMoney(dig)} en digital.');
    }
    return AnswerReply('Tienes ${formatMoney(l.totalAvailable)} disponibles: ${formatMoney(l.physicalTotal)} en físico y '
        '${formatMoney(l.digitalTotal)} en digital. (No incluye ingresos previstos.)');
  }

  return const AnswerReply('No entendí la pregunta. Prueba con «¿Cuánto debo en diciembre?» o escribe «ayuda».');
}

// --- Simulaciones ----------------------------------------------------------

AssistantReply _simulate(Ledger l, String raw, String t, Cents? amount, DateTime? date) {
  final today = l.today;
  final month = _extractMonth(raw, today);
  var from = month == null ? today : DateTime(month.year, month.month, 1);
  if (from.isBefore(today)) from = today;
  final to = month == null ? today.add(const Duration(days: 30)) : DateTime(month.year, month.month + 1, 0);
  final adjustments = <ScenarioAdjustment>[];
  final name = StringBuffer('Simulación');

  if (_has(raw, ['sin ingresos', 'no recibo', 'sin ingreso', 'no me pagan'])) {
    final days = raw.contains('semana') ? 7 : (raw.contains('quincena') ? 15 : (to.difference(from).inDays));
    final end = from.add(Duration(days: days - 1));
    adjustments.add(ScenarioAdjustment(kind: AdjustmentKind.skipIncomes, date: from, endDate: end));
    name.write(': sin ingresos del ${from.day}/${from.month} al ${end.day}/${end.month}');
  } else if (amount != null && _has(raw, ['gasto', 'gastar', 'compra', 'pago extra'])) {
    final d = date ?? from;
    adjustments.add(ScenarioAdjustment(kind: AdjustmentKind.expense, amount: amount, date: d, description: 'gasto extraordinario'));
    name.write(': gasto de ${formatMoney(amount)}');
  } else if (amount != null) {
    final freq = raw.contains('quincena') ? Frequency.biweekly
        : raw.contains('mensual') ? Frequency.monthly
        : raw.contains('diari') ? Frequency.daily
        : (raw.contains('semana') || raw.contains('semanal')) ? Frequency.weekly
        : null;
    // Si ya hay un ingreso recurrente con esa frecuencia, se simula cambiar su importe.
    final existing = freq == null ? null : l.recurrences.where((r) => r.isIncome && r.active && r.frequency == freq).firstOrNull;
    if (existing != null && month == null) {
      adjustments.add(ScenarioAdjustment(kind: AdjustmentKind.changeRecurrence, recurrenceId: existing.id, amount: amount));
      name.write(': ${existing.description} de ${formatMoney(amount)}');
    } else if (existing != null) {
      // Solo durante el mes indicado: se omiten los ingresos reales del periodo y se suma el nuevo.
      adjustments.add(ScenarioAdjustment(kind: AdjustmentKind.skipIncomes, date: from, endDate: to));
      adjustments.add(ScenarioAdjustment(kind: AdjustmentKind.income, amount: amount, frequency: freq, date: _firstOnOrAfter(existing, from), endDate: to));
      name.write(': ${DateFormat('MMMM', 'es_MX').format(from)} con ${formatMoney(amount)} ${freq!.label.toLowerCase()}');
    } else {
      adjustments.add(ScenarioAdjustment(kind: AdjustmentKind.income, amount: amount, frequency: freq, date: date ?? from, endDate: freq == null ? null : to));
      name.write(freq == null ? ': ingreso extra de ${formatMoney(amount)}' : ': ${formatMoney(amount)} ${freq.label.toLowerCase()}');
    }
  } else {
    return const AnswerReply('¿Qué quieres simular? Por ejemplo: «Simula diciembre con 400 semanales», '
        '«Simula una semana sin ingresos» o «Simula un gasto de 1500 el 10 de diciembre».');
  }

  final scenario = Scenario.create(name.toString(), adjustments, DateTime.now());
  final days = to.difference(today).inDays.clamp(7, 120);
  final base = projectBase(l, days: days);
  final sim = simulate(l, scenario, days: days);
  String line(ProjectionResult r) => 'saldo al ${_fd(r.daily.last.$1)}: ${formatMoney(r.finalBalance)} · '
      'más bajo: ${formatMoney(r.minimum.$2)} (${_fd(r.minimum.$1)})'
      '${r.firstNegative == null ? '' : ' · negativo desde el ${_fd(r.firstNegative!)}'}';
  return SimulationReply(
    '${scenario.name}\n\nCon la simulación → ${line(sim)}\nSin cambios → ${line(base)}\n\n'
    'Tus datos reales no cambiaron. Puedes verla en gráfica, guardarla o escribir «cancela esa simulación».',
    scenario,
  );
}

DateTime _firstOnOrAfter(Recurrence r, DateTime from) {
  final occ = r.occurrences(from, from.add(const Duration(days: 40)));
  return occ.isEmpty ? from : occ.first;
}
