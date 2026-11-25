import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drago/data/exporter.dart';
import 'package:drago/domain/ledger.dart';
import 'package:drago/domain/models.dart';
import 'package:drago/domain/reminders.dart';
import 'package:drago/domain/report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late Ledger l;
  late String cash;
  final now = DateTime(2026, 11, 25, 10);

  setUpAll(() => initializeDateFormatting('es_MX'));
  setUp(() {
    l = Ledger.withDefaults(clock: () => now);
    cash = l.accounts.firstWhere((a) => a.kind == AccountKind.physical).id;
  });

  Debt didi() => l.addDebt(name: 'DiDi Préstamos', total: 75000, startDate: now, installments: [
        (amount: 75000, dueDate: DateTime(2026, 12, 1)),
      ]);

  group('Recordatorios', () {
    test('Configuración inicial: 7, 2, 1 días antes y el día del vencimiento', () {
      didi();
      final r = buildReminders(l, const ReminderSettings());
      expect(r.map((x) => x.daysBefore), [7, 2, 1, 0]);
      expect(r.map((x) => x.fireAt), [
        DateTime(2026, 11, 24, 9), DateTime(2026, 11, 29, 9), DateTime(2026, 11, 30, 9), DateTime(2026, 12, 1, 9),
      ]);
      expect(r.last.body, contains('\$750.00 MXN'));
      expect(r.last.body, contains('DiDi Préstamos'));
      expect(r.last.body, contains('1 de diciembre'));
    });

    test('Solo se programan los futuros; los pasados van al centro de notificaciones', () {
      didi();
      final s = const ReminderSettings();
      expect(upcomingReminders(l, s, now).map((r) => r.daysBefore), [2, 1, 0]);
      final due = dueReminders(l, s, now);
      expect(due.single.daysBefore, 7); // el aviso de una semana antes ya ocurrió
    });

    test('Pagar la cuota cancela sus recordatorios', () {
      l.setBalance(accountId: cash, newBalance: 100000);
      final d = didi();
      expect(buildReminders(l, const ReminderSettings()), isNotEmpty);
      l.payInstallment(installmentId: l.installmentsOf(d.id).single.id, accountId: cash);
      expect(buildReminders(l, const ReminderSettings()), isEmpty);
    });

    test('Cambiar la fecha de la cuota mueve los recordatorios, con el mismo id', () {
      final d = didi();
      final inst = l.installmentsOf(d.id).single;
      final before = buildReminders(l, const ReminderSettings()).last;
      l.updateInstallment(inst.id, dueDate: DateTime(2026, 12, 3));
      final after = buildReminders(l, const ReminderSettings()).last;
      expect(after.fireAt, DateTime(2026, 12, 3, 9));
      expect(after.id, before.id); // reemplaza, no duplica
    });

    test('Sin duplicados y anticipación configurable', () {
      didi();
      final s = const ReminderSettings(daysBefore: [1, 1, 0], hour: 20, minute: 30);
      final r = buildReminders(l, s);
      expect(r.length, 2);
      expect(r.map((x) => x.id).toSet().length, 2);
      expect(r.first.fireAt, DateTime(2026, 11, 30, 20, 30));
      expect(buildReminders(l, s.copyWith(enabled: false)), isEmpty);
    });

    test('Ingresos previstos: recordatorio el mismo día para confirmarlos', () {
      l.addScheduledItem(accountId: cash, amount: 40000, date: DateTime(2026, 11, 28), description: 'Ingreso semanal');
      final r = buildReminders(l, const ReminderSettings());
      expect(r.single.title, contains('Ingreso previsto'));
      expect(buildReminders(l, const ReminderSettings(incomeReminders: false)), isEmpty);
    });

    test('Gastos programados también avisan', () {
      l.addScheduledItem(accountId: cash, amount: 15000, date: DateTime(2026, 11, 30), description: 'Renta', isIncome: false);
      expect(buildReminders(l, const ReminderSettings()).length, 4);
    });
  });

  group('Reportes y exportación', () {
    setUp(() {
      l.setBalance(accountId: cash, newBalance: 50000);
      l.addExpense(accountId: cash, amount: 8000, date: now, description: 'Comida, tacos', category: 'Comida');
      final d = didi();
      l.payInstallment(installmentId: l.installmentsOf(d.id).single.id, accountId: cash, amount: 30000);
      l.addScheduledItem(accountId: cash, amount: 40000, date: DateTime(2026, 11, 28), description: 'Ingreso semanal');
    });

    test('Excel completo: seis hojas, real y previsto separados', () {
      final tables = buildReport(l, Period.month(DateTime(2026, 11), 'Noviembre'));
      expect(tables.map((t) => t.name), ['Resumen', 'Movimientos', 'Deudas', 'Cuotas', 'Calendario', 'Proyección']);
      final cal = tables.firstWhere((t) => t.name == 'Calendario');
      expect(cal.rows.any((r) => r.last == 'Previsto'), isTrue);
      final movs = tables.firstWhere((t) => t.name == 'Movimientos');
      expect(movs.rows.every((r) => r.last == 'Real'), isTrue);
      final resumen = tables.first.rows;
      final total = resumen.firstWhere((r) => r.first == 'Total disponible')[1] as Amount;
      expect(total.cents, 12000); // 500 - 80 - 300; el ingreso previsto NO se suma
    });

    test('Solo deudas', () {
      final t = buildReport(l, Period.month(DateTime(2026, 11), 'x'), scope: ReportScope.debtsOnly);
      expect(t.map((x) => x.name), ['Deudas', 'Cuotas']);
      expect((t.first.rows.single[5] as Amount).cents, 45000); // pendiente
    });

    test('CSV con comillas, importes con signo y BOM', () {
      final csv = toCsv(buildReport(l, Period.month(DateTime(2026, 11), 'x'), scope: ReportScope.movementsOnly).single);
      expect(csv.startsWith('﻿'), isTrue);
      expect(csv, contains('"Comida, tacos"'));
      expect(csv, contains('-80.00'));
      expect(csv, contains('-300.00'));
    });

    test('El archivo .xlsx es válido y contiene las hojas', () {
      final bytes = buildXlsx(buildReport(l, Period.month(DateTime(2026, 11), 'x')));
      final zip = ZipDecoder().decodeBytes(bytes);
      final workbook = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
      for (final name in ['Resumen', 'Movimientos', 'Deudas', 'Cuotas', 'Calendario', 'Proyección']) {
        expect(workbook, contains('name="$name"'));
      }
      expect(workbook, isNot(contains('Sheet1')));
    });

    test('Periodo: movimientos fuera del rango no se incluyen', () {
      final t = buildReport(l, Period.month(DateTime(2026, 10), 'Octubre'), scope: ReportScope.movementsOnly).single;
      expect(t.rows, isEmpty);
    });
  });
}
