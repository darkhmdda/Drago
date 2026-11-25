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
// Ingresos previstos
// ---------------------------------------------------------------------------

enum ScheduledStatus { expected, received, notReceived }

extension ScheduledStatusLabel on ScheduledStatus {
  String get label => switch (this) {
        ScheduledStatus.expected => 'Previsto',
        ScheduledStatus.received => 'Recibido',
        ScheduledStatus.notReceived => 'No recibido',
      };
}

/// Ingreso esperado. NUNCA afecta el saldo real mientras esté previsto.
class ScheduledIncome {
  final String id;
  final DateTime date;
  final Cents amount;
  final String description;
  final String accountId;
  final ScheduledStatus status;

  /// Movimiento real creado al confirmar la recepción.
  final String? transactionId;

  const ScheduledIncome({
    required this.id,
    required this.date,
    required this.amount,
    required this.description,
    required this.accountId,
    this.status = ScheduledStatus.expected,
    this.transactionId,
  });

  ScheduledIncome copyWith({ScheduledStatus? status, String? transactionId, bool clearTransaction = false}) =>
      ScheduledIncome(
        id: id,
        date: date,
        amount: amount,
        description: description,
        accountId: accountId,
        status: status ?? this.status,
        transactionId: clearTransaction ? null : (transactionId ?? this.transactionId),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': _d(date),
        'amount': amount,
        'description': description,
        'accountId': accountId,
        'status': status.name,
        'transactionId': transactionId,
      };

  factory ScheduledIncome.fromJson(Map<String, dynamic> j) => ScheduledIncome(
        id: j['id'],
        date: _p(j['date']),
        amount: j['amount'],
        description: j['description'] ?? '',
        accountId: j['accountId'],
        status: ScheduledStatus.values.byName(j['status']),
        transactionId: j['transactionId'],
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
