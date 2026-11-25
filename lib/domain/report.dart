import 'ledger.dart';
import 'models.dart';
import 'money.dart';

/// Importe en una celda de reporte (se exporta como número, no como texto).
class Amount {
  final Cents cents;
  const Amount(this.cents);
  String get plain => '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
}

/// Fecha (sin hora) en una celda de reporte.
class Day {
  final DateTime date;
  const Day(this.date);
  String get iso =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Una hoja: título, encabezados y filas. Las celdas son String, int,
/// [Amount], [Day] o null.
class ReportTable {
  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;
  const ReportTable(this.name, this.headers, this.rows);
}

class Period {
  final DateTime from;
  final DateTime to;
  final String label;
  const Period(this.from, this.to, this.label);

  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  static Period month(DateTime m, String label) =>
      Period(DateTime(m.year, m.month, 1), DateTime(m.year, m.month + 1, 0), label);
}

enum ReportScope { full, debtsOnly, movementsOnly }

/// Construye las hojas del reporte. Los registros reales y los previstos se
/// distinguen siempre con la columna «Naturaleza».
List<ReportTable> buildReport(Ledger l, Period p, {ReportScope scope = ReportScope.full}) {
  final tables = <ReportTable>[];
  if (scope == ReportScope.full) tables.add(_summary(l, p));
  if (scope != ReportScope.debtsOnly) tables.add(_movements(l, p));
  if (scope != ReportScope.movementsOnly) {
    tables.add(_debts(l));
    tables.add(_installments(l));
  }
  if (scope == ReportScope.full) {
    tables.add(_calendar(l, p));
    tables.add(_projection(l));
  }
  return tables;
}

ReportTable _summary(Ledger l, Period p) {
  var inc = 0, exp = 0, debt = 0;
  for (final t in l.transactions) {
    if (!p.contains(t.date)) continue;
    switch (t.type) {
      case TxType.income:
        inc += t.amount;
      case TxType.expense:
        exp += t.amount;
      case TxType.debtPayment:
        debt += t.amount;
      default:
        break;
    }
  }
  return ReportTable('Resumen', const ['Concepto', 'Valor'], [
    ['Periodo', p.label],
    ['Desde', Day(p.from)],
    ['Hasta', Day(p.to)],
    ['Generado', Day(l.today)],
    [null, null],
    ['SALDOS REALES (hoy)', null],
    for (final a in l.accounts.where((a) => !a.archived)) ['${a.name} (${a.kind.label.toLowerCase()})', Amount(l.balance(a.id))],
    ['Dinero físico', Amount(l.physicalTotal)],
    ['Dinero digital', Amount(l.digitalTotal)],
    ['Total disponible', Amount(l.totalAvailable)],
    [null, null],
    ['MOVIMIENTOS REALES DEL PERIODO', null],
    ['Ingresos recibidos', Amount(inc)],
    ['Gastos', Amount(-exp)],
    ['Pagos de deudas', Amount(-debt)],
    ['Balance', Amount(inc - exp - debt)],
    [null, null],
    ['DEUDAS', null],
    ['Deudas activas', l.debts.where((d) => d.status == DebtStatus.active).length],
    ['Total pendiente', Amount(l.totalPendingDebt)],
    [null, null],
    ['Nota', 'Los saldos y movimientos son reales. Lo previsto está en las hojas Calendario y Proyección.'],
  ]);
}

String? _debtName(Ledger l, String? id) {
  if (id == null) return null;
  for (final d in l.debts) {
    if (d.id == id) return d.name;
  }
  return null;
}

ReportTable _movements(Ledger l, Period p) {
  final txs = l.transactions.where((t) => p.contains(t.date)).toList()
    ..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
  return ReportTable(
    'Movimientos',
    const ['Fecha', 'Tipo', 'Descripción', 'Cuenta', 'Cuenta destino', 'Categoría', 'Deuda', 'Importe', 'Naturaleza'],
    [
      for (final t in txs)
        [
          Day(t.date),
          t.type.label,
          t.description,
          l.account(t.accountId).name,
          t.toAccountId == null ? null : l.account(t.toAccountId!).name,
          t.category,
          _debtName(l, t.debtId),
          // Transferencias: importe sin signo (no es ingreso ni gasto).
          Amount(t.type == TxType.transfer ? t.amount : t.effectOn(t.accountId)),
          'Real',
        ],
    ],
  );
}

ReportTable _debts(Ledger l) => ReportTable(
      'Deudas',
      const ['Deuda', 'Estado', 'Inicio', 'Monto original', 'Pagado', 'Pendiente', 'Suma de cuotas pendientes', 'Descripción'],
      [
        for (final d in l.debts)
          () {
            final s = l.summaryOf(d.id);
            return [d.name, d.status.label, Day(d.startDate), Amount(s.original), Amount(s.paid), Amount(s.remaining),
              Amount(s.pendingInstallments), d.description];
          }(),
      ],
    );

ReportTable _installments(Ledger l) => ReportTable(
      'Cuotas',
      const ['Deuda', 'Cuota', 'Vencimiento', 'Importe', 'Pagado', 'Falta', 'Estado'],
      [
        for (final d in l.debts)
          for (final i in l.installmentsOf(d.id))
            [d.name, i.number, Day(i.dueDate), Amount(i.amount), Amount(l.paidForInstallment(i.id)),
              Amount(l.remainingForInstallment(i.id)), l.installmentStatus(i).label],
      ],
    );

ReportTable _calendar(Ledger l, Period p) => ReportTable(
      'Calendario',
      const ['Fecha', 'Evento', 'Tipo', 'Importe', 'Estado', 'Naturaleza'],
      [
        for (final e in l.eventsBetween(p.from, p.to))
          [
            Day(e.date),
            e.title,
            switch (e.kind) { EventKind.income => 'Ingreso', EventKind.expense => 'Gasto', EventKind.installment => 'Cuota' },
            Amount(e.signed),
            e.statusLabel,
            e.done ? 'Real (confirmado)' : (e.skipped ? 'No ocurrió' : 'Previsto'),
          ],
      ],
    );

ReportTable _projection(Ledger l) => ReportTable(
      'Proyección',
      const ['Fecha', 'Evento', 'Importe', 'Saldo proyectado', 'Se suma', 'Naturaleza'],
      [
        [Day(l.today), 'Saldo real de hoy', null, Amount(l.totalAvailable), null, 'Real'],
        for (final pt in l.projection(days: 90))
          [Day(pt.event.date), pt.event.title, Amount(pt.event.signed), Amount(pt.balance), pt.counted ? 'Sí' : 'No (atrasado)',
            'Previsto'],
      ],
    );

/// CSV (separado por comas, UTF-8 con BOM para que Excel respete acentos).
String toCsv(ReportTable t) {
  String cell(Object? v) {
    final s = switch (v) {
      null => '',
      Amount a => a.plain,
      Day d => d.iso,
      _ => v.toString(),
    };
    return (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final b = StringBuffer('﻿');
  b.writeln(t.headers.map(cell).join(','));
  for (final r in t.rows) {
    b.writeln(r.map(cell).join(','));
  }
  return b.toString();
}
