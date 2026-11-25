import 'package:uuid/uuid.dart';

import 'ledger.dart';
import 'models.dart';
import 'money.dart';

DateTime _p(String s) => DateTime.parse(s);
String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Tipos de cambio hipotético que puede tener una simulación.
enum AdjustmentKind {
  /// Un ingreso extra en una fecha (o recurrente si tiene [ScenarioAdjustment.frequency]).
  income,

  /// Un gasto extraordinario en una fecha.
  expense,

  /// No llega ningún ingreso previsto entre dos fechas («una semana sin ingresos»).
  skipIncomes,

  /// Cambiar el importe de un ingreso/gasto recurrente («$500 en vez de $400»).
  changeRecurrence,

  /// Mover (adelantar o atrasar) una cuota a otra fecha.
  moveInstallment,
}

class ScenarioAdjustment {
  final AdjustmentKind kind;
  final Cents amount;
  final DateTime? date;
  final DateTime? endDate;
  final Frequency? frequency;
  final String? recurrenceId;
  final String? installmentId;
  final String description;

  const ScenarioAdjustment({
    required this.kind,
    this.amount = 0,
    this.date,
    this.endDate,
    this.frequency,
    this.recurrenceId,
    this.installmentId,
    this.description = '',
  });

  /// Texto legible para listas.
  String describe(Ledger l) {
    String? f(DateTime? d) => d == null ? null : '${d.day}/${d.month}';
    switch (kind) {
      case AdjustmentKind.income:
        return frequency == null
            ? 'Ingreso extra de ${formatMoney(amount)} el ${f(date)}'
            : 'Ingreso ${frequency!.label.toLowerCase()} de ${formatMoney(amount)} desde el ${f(date)}'
                '${endDate == null ? '' : ' hasta el ${f(endDate)}'}';
      case AdjustmentKind.expense:
        return 'Gasto extraordinario de ${formatMoney(amount)} el ${f(date)}${description.isEmpty ? '' : ' ($description)'}';
      case AdjustmentKind.skipIncomes:
        return 'Sin ingresos del ${f(date)} al ${f(endDate)}';
      case AdjustmentKind.changeRecurrence:
        final r = l.recurrences.where((x) => x.id == recurrenceId).firstOrNull;
        return '${r?.description ?? 'Regla recurrente'}: ${formatMoney(amount)} en lugar de ${r == null ? '—' : formatMoney(r.amount)}';
      case AdjustmentKind.moveInstallment:
        final i = l.installments.where((x) => x.id == installmentId).firstOrNull;
        final name = i == null ? 'Cuota' : '${l.debts.where((d) => d.id == i.debtId).firstOrNull?.name ?? 'Deuda'} · cuota ${i.number}';
        return '$name: pagar el ${f(date)}${i == null ? '' : ' (vence el ${f(i.dueDate)})'}';
    }
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'amount': amount,
        'date': date == null ? null : _d(date!),
        'endDate': endDate == null ? null : _d(endDate!),
        'frequency': frequency?.name,
        'recurrenceId': recurrenceId,
        'installmentId': installmentId,
        'description': description,
      };

  factory ScenarioAdjustment.fromJson(Map<String, dynamic> j) => ScenarioAdjustment(
        kind: AdjustmentKind.values.byName(j['kind']),
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        date: j['date'] == null ? null : _p(j['date']),
        endDate: j['endDate'] == null ? null : _p(j['endDate']),
        frequency: j['frequency'] == null ? null : Frequency.values.byName(j['frequency']),
        recurrenceId: j['recurrenceId'],
        installmentId: j['installmentId'],
        description: j['description'] ?? '',
      );
}

/// Simulación guardada. NUNCA modifica los datos reales: se aplica sobre una
/// copia del libro y solo se usa para calcular la proyección.
class Scenario {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<ScenarioAdjustment> adjustments;

  const Scenario({required this.id, required this.name, required this.createdAt, this.adjustments = const []});

  static Scenario create(String name, List<ScenarioAdjustment> adjustments, DateTime now) =>
      Scenario(id: const Uuid().v4(), name: name, createdAt: now, adjustments: adjustments);

  Scenario copyWith({String? name, List<ScenarioAdjustment>? adjustments}) =>
      Scenario(id: id, name: name ?? this.name, createdAt: createdAt, adjustments: adjustments ?? this.adjustments);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'adjustments': adjustments.map((a) => a.toJson()).toList(),
      };

  factory Scenario.fromJson(Map<String, dynamic> j) => Scenario(
        id: j['id'],
        name: j['name'] ?? 'Simulación',
        createdAt: DateTime.parse(j['createdAt']),
        adjustments: ((j['adjustments'] as List?) ?? const [])
            .map((e) => ScenarioAdjustment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Resultado de proyectar (con o sin simulación).
class ProjectionResult {
  final Cents startBalance;
  final List<ProjectionPoint> points;

  /// Saldo al cierre de cada día, desde hoy hasta el horizonte.
  final List<(DateTime, Cents)> daily;

  /// Cambios de la simulación que ya no se pudieron aplicar (por ejemplo,
  /// una cuota que se eliminó).
  final List<String> skipped;

  const ProjectionResult(this.startBalance, this.points, this.daily, {this.skipped = const []});

  Cents get finalBalance => daily.isEmpty ? startBalance : daily.last.$2;

  (DateTime, Cents) get minimum => daily.reduce((a, b) => b.$2 < a.$2 ? b : a);

  DateTime? get firstNegative => daily.where((d) => d.$2 < 0).map((d) => d.$1).firstOrNull;

  Cents get totalIn => points.where((p) => p.counted && p.event.isIncome).fold<int>(0, (s, p) => s + p.event.amount);
  Cents get totalOut => points.where((p) => p.counted && !p.event.isIncome).fold<int>(0, (s, p) => s + p.event.amount);
}

ProjectionResult _result(Ledger l, int days, {List<String> skipped = const []}) {
  final points = l.projection(days: days);
  final start = l.totalAvailable;
  final daily = <(DateTime, Cents)>[];
  var balance = start;
  var k = 0;
  for (var d = 0; d <= days; d++) {
    final day = DateTime(l.today.year, l.today.month, l.today.day + d);
    // Los eventos vencidos (antes de hoy) se aplican el primer día.
    while (k < points.length && !points[k].event.date.isAfter(day)) {
      if (points[k].counted) balance = points[k].balance;
      k++;
    }
    daily.add((day, balance));
  }
  return ProjectionResult(start, points, daily, skipped: skipped);
}

/// Proyección sin cambios hipotéticos.
ProjectionResult projectBase(Ledger real, {int days = 60}) => _result(real, days);

/// Aplica la simulación sobre una COPIA y proyecta. El libro real no cambia.
ProjectionResult simulate(Ledger real, Scenario s, {int days = 60}) {
  final copy = real.clone();
  final skipped = <String>[];
  final cash = copy.activeAccounts.where((a) => a.kind == AccountKind.physical).firstOrNull ?? copy.activeAccounts.first;
  for (final a in s.adjustments) {
    try {
      switch (a.kind) {
        case AdjustmentKind.income:
          if (a.frequency == null) {
            copy.addScheduledItem(accountId: cash.id, amount: a.amount, date: a.date ?? copy.today, description: 'Simulado: ingreso');
          } else {
            copy.addRecurrence(
                description: 'Simulado: ingreso',
                amount: a.amount,
                accountId: cash.id,
                frequency: a.frequency!,
                startDate: a.date ?? copy.today,
                endDate: a.endDate);
          }
        case AdjustmentKind.expense:
          copy.addScheduledItem(
              accountId: cash.id,
              amount: a.amount,
              date: a.date ?? copy.today,
              description: a.description.isEmpty ? 'Simulado: gasto' : 'Simulado: ${a.description}',
              isIncome: false);
        case AdjustmentKind.skipIncomes:
          final from = a.date ?? copy.today;
          final to = a.endDate ?? from;
          for (final e in copy.eventsBetween(from, to).where((e) => e.isIncome && e.isOpen)) {
            copy.markScheduledSkipped(copy.ensureScheduledItem(
                scheduledItemId: e.scheduledItemId, recurrenceId: e.recurrenceId, occurrenceDate: e.occurrenceDate));
          }
        case AdjustmentKind.changeRecurrence:
          copy.updateRecurrence(a.recurrenceId!, amount: a.amount);
        case AdjustmentKind.moveInstallment:
          copy.updateInstallment(a.installmentId!, dueDate: a.date);
      }
    } catch (_) {
      skipped.add(a.describe(real));
    }
  }
  return _result(copy, days, skipped: skipped);
}

/// Historial de saldos reales: saldo físico y digital al cierre de cada día
/// entre [from] y [to] (solo movimientos confirmados).
List<(DateTime, Cents, Cents)> balanceHistory(Ledger l, DateTime from, DateTime to) {
  final kindOf = {for (final a in l.accounts) a.id: a.kind};
  final txs = [...l.transactions]..sort((a, b) => a.date.compareTo(b.date));
  var phys = 0, dig = 0, k = 0;
  void apply(Transaction t) {
    for (final id in {t.accountId, ?t.toAccountId}) {
      final e = t.effectOn(id);
      if (kindOf[id] == AccountKind.physical) {
        phys += e;
      } else {
        dig += e;
      }
    }
  }

  final out = <(DateTime, Cents, Cents)>[];
  for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    while (k < txs.length && !txs[k].date.isAfter(d)) {
      apply(txs[k]);
      k++;
    }
    out.add((d, phys, dig));
  }
  return out;
}
