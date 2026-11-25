import 'money.dart';

/// Fecha sin hora (las fechas financieras se manejan por día).
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime _p(String s) => DateTime.parse(s);

// ---------------------------------------------------------------------------
// Cuentas
// ---------------------------------------------------------------------------

/// Dinero físico (efectivo) o dinero digital (bancos, tarjetas, billeteras).
enum AccountKind { physical, digital }

extension AccountKindLabel on AccountKind {
  String get label => this == AccountKind.physical ? 'Dinero físico' : 'Dinero digital';
}

class Account {
  final String id;
  final String name;
  final AccountKind kind;
  final bool archived;

  const Account({required this.id, required this.name, required this.kind, this.archived = false});

  Account copyWith({String? name, bool? archived}) =>
      Account(id: id, name: name ?? this.name, kind: kind, archived: archived ?? this.archived);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name, 'archived': archived};
  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'],
        name: j['name'],
        kind: AccountKind.values.byName(j['kind']),
        archived: j['archived'] ?? false,
      );
}

// ---------------------------------------------------------------------------
// Movimientos reales
// ---------------------------------------------------------------------------

enum TxType { income, expense, debtPayment, transfer, adjustment }

extension TxTypeLabel on TxType {
  String get label => switch (this) {
        TxType.income => 'Ingreso',
        TxType.expense => 'Gasto',
        TxType.debtPayment => 'Pago de deuda',
        TxType.transfer => 'Transferencia',
        TxType.adjustment => 'Ajuste manual',
      };
}

/// Un movimiento real ya ocurrido.
///
/// [amount] siempre es positivo, salvo en [TxType.adjustment], donde el signo
/// indica si el ajuste sube (+) o baja (-) el saldo de la cuenta.
class Transaction {
  final String id;
  final DateTime date;
  final Cents amount;
  final TxType type;
  final String description;
  final String accountId;

  /// Cuenta destino (solo transferencias).
  final String? toAccountId;
  final String? category;
  final String? debtId;
  final String? installmentId;

  /// Ingreso previsto que originó este movimiento al confirmarse.
  final String? scheduledItemId;
  final DateTime createdAt;

  const Transaction({
    required this.id,
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
    required this.accountId,
    this.toAccountId,
    this.category,
    this.debtId,
    this.installmentId,
    this.scheduledItemId,
    required this.createdAt,
  });

  /// Efecto de este movimiento sobre el saldo de [account].
  Cents effectOn(String account) {
    switch (type) {
      case TxType.income:
        return account == accountId ? amount : 0;
      case TxType.expense:
      case TxType.debtPayment:
        return account == accountId ? -amount : 0;
      case TxType.adjustment:
        return account == accountId ? amount : 0;
      case TxType.transfer:
        if (account == accountId) return -amount;
        if (account == toAccountId) return amount;
        return 0;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': _d(date),
        'amount': amount,
        'type': type.name,
        'description': description,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'category': category,
        'debtId': debtId,
        'installmentId': installmentId,
        'scheduledItemId': scheduledItemId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'],
        date: _p(j['date']),
        amount: j['amount'],
        type: TxType.values.byName(j['type']),
        description: j['description'] ?? '',
        accountId: j['accountId'],
        toAccountId: j['toAccountId'],
        category: j['category'],
        debtId: j['debtId'],
        installmentId: j['installmentId'],
        scheduledItemId: j['scheduledItemId'],
        createdAt: DateTime.parse(j['createdAt']),
      );
}

// ---------------------------------------------------------------------------
// Deudas y cuotas
// ---------------------------------------------------------------------------

enum DebtStatus { active, settled, cancelled }

extension DebtStatusLabel on DebtStatus {
  String get label => switch (this) {
        DebtStatus.active => 'Activa',
        DebtStatus.settled => 'Liquidada',
        DebtStatus.cancelled => 'Cancelada',
      };
}

class Debt {
  final String id;
  final String name;

  /// Monto total a pagar (puede no coincidir con la suma de cuotas).
  final Cents total;
  final DateTime startDate;
  final String description;
  final DebtStatus status;

  const Debt({
    required this.id,
    required this.name,
    required this.total,
    required this.startDate,
    this.description = '',
    this.status = DebtStatus.active,
  });

  Debt copyWith({String? name, Cents? total, DateTime? startDate, String? description, DebtStatus? status}) => Debt(
        id: id,
        name: name ?? this.name,
        total: total ?? this.total,
        startDate: startDate ?? this.startDate,
        description: description ?? this.description,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'total': total,
        'startDate': _d(startDate),
        'description': description,
        'status': status.name,
      };

  factory Debt.fromJson(Map<String, dynamic> j) => Debt(
        id: j['id'],
        name: j['name'],
        total: j['total'],
        startDate: _p(j['startDate']),
        description: j['description'] ?? '',
        status: DebtStatus.values.byName(j['status']),
      );
}

enum InstallmentStatus { pending, partial, paid, overdue, cancelled }

extension InstallmentStatusLabel on InstallmentStatus {
  String get label => switch (this) {
        InstallmentStatus.pending => 'No pagado',
        InstallmentStatus.partial => 'Abonado',
        InstallmentStatus.paid => 'Pagado',
        InstallmentStatus.overdue => 'Vencido',
        InstallmentStatus.cancelled => 'Cancelado',
      };
}

/// Cuota individual. Cada una tiene su propio importe y vencimiento.
/// Su estado de pago se calcula a partir de los movimientos (abonos) vinculados.
class Installment {
  final String id;
  final String debtId;
  final int number;
  final Cents amount;
  final DateTime dueDate;
  final bool cancelled;

  const Installment({
    required this.id,
    required this.debtId,
    required this.number,
    required this.amount,
    required this.dueDate,
    this.cancelled = false,
  });

  Installment copyWith({int? number, Cents? amount, DateTime? dueDate, bool? cancelled}) => Installment(
        id: id,
        debtId: debtId,
        number: number ?? this.number,
        amount: amount ?? this.amount,
        dueDate: dueDate ?? this.dueDate,
        cancelled: cancelled ?? this.cancelled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'debtId': debtId,
        'number': number,
        'amount': amount,
        'dueDate': _d(dueDate),
        'cancelled': cancelled,
      };

  factory Installment.fromJson(Map<String, dynamic> j) => Installment(
        id: j['id'],
        debtId: j['debtId'],
        number: j['number'],
        amount: j['amount'],
        dueDate: _p(j['dueDate']),
        cancelled: j['cancelled'] ?? false,
      );
}

// ---------------------------------------------------------------------------
// Ingresos y gastos previstos
// ---------------------------------------------------------------------------

enum ScheduledStatus { expected, received, notReceived }

extension ScheduledStatusLabel on ScheduledStatus {
  String labelFor(bool isIncome) => switch (this) {
        ScheduledStatus.expected => 'Previsto',
        ScheduledStatus.received => isIncome ? 'Recibido' : 'Pagado',
        ScheduledStatus.notReceived => isIncome ? 'No recibido' : 'Cancelado',
      };
}

/// Ingreso o gasto esperado en una fecha. NUNCA afecta el saldo real
/// mientras esté previsto; al confirmarse genera un movimiento real.
///
/// Si proviene de una regla recurrente, [recurrenceId] + [occurrenceDate]
/// identifican la ocurrencia, de modo que nunca se duplique.
class ScheduledItem {
  final String id;
  final DateTime date;
  final Cents amount;
  final String description;
  final String accountId;
  final bool isIncome;
  final ScheduledStatus status;

  /// Movimiento real creado al confirmar.
  final String? transactionId;
  final String? recurrenceId;
  final DateTime? occurrenceDate;

  const ScheduledItem({
    required this.id,
    required this.date,
    required this.amount,
    required this.description,
    required this.accountId,
    this.isIncome = true,
    this.status = ScheduledStatus.expected,
    this.transactionId,
    this.recurrenceId,
    this.occurrenceDate,
  });

  ScheduledItem copyWith({
    DateTime? date,
    Cents? amount,
    String? description,
    String? accountId,
    ScheduledStatus? status,
    String? transactionId,
    bool clearTransaction = false,
    bool clearRecurrence = false,
  }) =>
      ScheduledItem(
        id: id,
        date: date ?? this.date,
        amount: amount ?? this.amount,
        description: description ?? this.description,
        accountId: accountId ?? this.accountId,
        isIncome: isIncome,
        status: status ?? this.status,
        transactionId: clearTransaction ? null : (transactionId ?? this.transactionId),
        recurrenceId: clearRecurrence ? null : recurrenceId,
        occurrenceDate: clearRecurrence ? null : occurrenceDate,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': _d(date),
        'amount': amount,
        'description': description,
        'accountId': accountId,
        'isIncome': isIncome,
        'status': status.name,
        'transactionId': transactionId,
        'recurrenceId': recurrenceId,
        'occurrenceDate': occurrenceDate == null ? null : _d(occurrenceDate!),
      };

  factory ScheduledItem.fromJson(Map<String, dynamic> j) => ScheduledItem(
        id: j['id'],
        date: _p(j['date']),
        amount: j['amount'],
        description: j['description'] ?? '',
        accountId: j['accountId'],
        isIncome: j['isIncome'] ?? true,
        status: ScheduledStatus.values.byName(j['status']),
        transactionId: j['transactionId'],
        recurrenceId: j['recurrenceId'],
        occurrenceDate: j['occurrenceDate'] == null ? null : _p(j['occurrenceDate']),
      );
}

// ---------------------------------------------------------------------------
// Reglas recurrentes
// ---------------------------------------------------------------------------

enum Frequency { daily, weekly, biweekly, monthly, custom }

extension FrequencyLabel on Frequency {
  String get label => switch (this) {
        Frequency.daily => 'Diaria',
        Frequency.weekly => 'Semanal',
        Frequency.biweekly => 'Quincenal',
        Frequency.monthly => 'Mensual',
        Frequency.custom => 'Personalizada',
      };
}

int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

/// Regla de ingreso (o gasto) recurrente, por ejemplo «$400 cada sábado».
/// Sus ocurrencias se calculan; solo se guardan cuando el usuario actúa
/// sobre una (confirmarla, marcarla como no recibida o ajustarla).
class Recurrence {
  final String id;
  final String description;
  final Cents amount;
  final String accountId;
  final bool isIncome;
  final Frequency frequency;

  /// Cada cuántos días (solo [Frequency.custom]).
  final int intervalDays;
  final DateTime startDate;
  final DateTime? endDate;
  final bool active;

  const Recurrence({
    required this.id,
    required this.description,
    required this.amount,
    required this.accountId,
    this.isIncome = true,
    required this.frequency,
    this.intervalDays = 7,
    required this.startDate,
    this.endDate,
    this.active = true,
  });

  Recurrence copyWith({
    String? description,
    Cents? amount,
    String? accountId,
    Frequency? frequency,
    int? intervalDays,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEnd = false,
    bool? active,
  }) =>
      Recurrence(
        id: id,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        accountId: accountId ?? this.accountId,
        isIncome: isIncome,
        frequency: frequency ?? this.frequency,
        intervalDays: intervalDays ?? this.intervalDays,
        startDate: startDate ?? this.startDate,
        endDate: clearEnd ? null : (endDate ?? this.endDate),
        active: active ?? this.active,
      );

  /// Texto legible: «Cada sábado», «Día 1 y 16 de cada mes», etc.
  String get scheduleLabel {
    const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    switch (frequency) {
      case Frequency.daily:
        return 'Todos los días';
      case Frequency.weekly:
        return 'Cada ${days[startDate.weekday - 1]}';
      case Frequency.biweekly:
        final (a, b) = biweeklyDays;
        return 'Días $a y $b de cada mes';
      case Frequency.monthly:
        return 'Día ${startDate.day} de cada mes';
      case Frequency.custom:
        return 'Cada $intervalDays días';
    }
  }

  /// Días del mes para la frecuencia quincenal (ej. 1 y 16, 15 y 30).
  (int, int) get biweeklyDays {
    final d = startDate.day;
    return d <= 15 ? (d, d + 15) : (d - 15, d);
  }

  /// Fechas de las ocurrencias entre [from] y [to] (inclusive).
  List<DateTime> occurrences(DateTime from, DateTime to) {
    final start = dayOf(startDate);
    var lo = dayOf(from).isBefore(start) ? start : dayOf(from);
    var hi = dayOf(to);
    if (endDate != null && dayOf(endDate!).isBefore(hi)) hi = dayOf(endDate!);
    if (hi.isBefore(lo)) return const [];
    final out = <DateTime>[];
    switch (frequency) {
      case Frequency.daily:
      case Frequency.weekly:
      case Frequency.custom:
        final step = switch (frequency) { Frequency.daily => 1, Frequency.weekly => 7, _ => intervalDays < 1 ? 1 : intervalDays };
        final offset = lo.difference(start).inDays;
        var k = (offset + step - 1) ~/ step;
        while (true) {
          final d = DateTime(start.year, start.month, start.day + k * step);
          if (d.isAfter(hi)) break;
          out.add(d);
          k++;
        }
      case Frequency.monthly:
      case Frequency.biweekly:
        final wanted = frequency == Frequency.monthly ? [startDate.day] : [biweeklyDays.$1, biweeklyDays.$2];
        var y = lo.year, m = lo.month;
        while (!DateTime(y, m, 1).isAfter(hi)) {
          for (final day in wanted) {
            final d = DateTime(y, m, day.clamp(1, _daysInMonth(y, m)));
            if (!d.isBefore(lo) && !d.isAfter(hi) && (out.isEmpty || out.last != d)) out.add(d);
          }
          m++;
          if (m > 12) {
            m = 1;
            y++;
          }
        }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'amount': amount,
        'accountId': accountId,
        'isIncome': isIncome,
        'frequency': frequency.name,
        'intervalDays': intervalDays,
        'startDate': _d(startDate),
        'endDate': endDate == null ? null : _d(endDate!),
        'active': active,
      };

  factory Recurrence.fromJson(Map<String, dynamic> j) => Recurrence(
        id: j['id'],
        description: j['description'] ?? '',
        amount: j['amount'],
        accountId: j['accountId'],
        isIncome: j['isIncome'] ?? true,
        frequency: Frequency.values.byName(j['frequency']),
        intervalDays: j['intervalDays'] ?? 7,
        startDate: _p(j['startDate']),
        endDate: j['endDate'] == null ? null : _p(j['endDate']),
        active: j['active'] ?? true,
      );
}

// ---------------------------------------------------------------------------
// Auditoría
// ---------------------------------------------------------------------------

class AuditEntry {
  final String id;
  final DateTime at;
  final String action;
  final String details;

  const AuditEntry({required this.id, required this.at, required this.action, required this.details});

  Map<String, dynamic> toJson() => {'id': id, 'at': at.toIso8601String(), 'action': action, 'details': details};
  factory AuditEntry.fromJson(Map<String, dynamic> j) =>
      AuditEntry(id: j['id'], at: DateTime.parse(j['at']), action: j['action'], details: j['details']);
}
