import 'dart:convert';

import 'package:drago/domain/ledger.dart';
import 'package:drago/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Ledger l;
  late String cash;
  late String bank;
  // Miércoles 25 de noviembre de 2026.
  final now = DateTime(2026, 11, 25, 10);

  setUp(() {
    l = Ledger.withDefaults(clock: () => now);
    cash = l.accounts.firstWhere((a) => a.kind == AccountKind.physical).id;
    bank = l.accounts.firstWhere((a) => a.kind == AccountKind.digital).id;
  });

  Recurrence weekly400() => l.addRecurrence(
        description: 'Ingreso semanal',
        amount: 40000,
        accountId: cash,
        frequency: Frequency.weekly,
        startDate: DateTime(2026, 11, 28), // sábado
      );

  group('Frecuencias', () {
    Recurrence rec(Frequency f, DateTime start, {int interval = 7}) =>
        Recurrence(id: 'r', description: 'x', amount: 1, accountId: 'a', frequency: f, startDate: start, intervalDays: interval);

    test('Semanal: cada sábado', () {
      final d = rec(Frequency.weekly, DateTime(2026, 11, 28)).occurrences(DateTime(2026, 11, 1), DateTime(2026, 12, 31));
      expect(d, [for (final day in [28]) DateTime(2026, 11, day), for (final day in [5, 12, 19, 26]) DateTime(2026, 12, day)]);
      expect(d.every((x) => x.weekday == DateTime.saturday), isTrue);
    });

    test('Diaria', () {
      expect(rec(Frequency.daily, DateTime(2026, 11, 1)).occurrences(DateTime(2026, 11, 29), DateTime(2026, 12, 2)).length, 4);
    });

    test('Quincenal: días 1 y 16', () {
      expect(rec(Frequency.biweekly, DateTime(2026, 12, 1)).occurrences(DateTime(2026, 12, 1), DateTime(2027, 1, 31)),
          [DateTime(2026, 12, 1), DateTime(2026, 12, 16), DateTime(2027, 1, 1), DateTime(2027, 1, 16)]);
    });

    test('Quincenal: 15 y 30 se ajusta en febrero', () {
      expect(rec(Frequency.biweekly, DateTime(2027, 1, 30)).occurrences(DateTime(2027, 2, 1), DateTime(2027, 2, 28)),
          [DateTime(2027, 2, 15), DateTime(2027, 2, 28)]);
    });

    test('Mensual: día 31 se ajusta al último día del mes', () {
      expect(rec(Frequency.monthly, DateTime(2026, 10, 31)).occurrences(DateTime(2026, 11, 1), DateTime(2027, 2, 28)),
          [DateTime(2026, 11, 30), DateTime(2026, 12, 31), DateTime(2027, 1, 31), DateTime(2027, 2, 28)]);
    });

    test('Personalizada: cada 10 días, respeta la fecha final', () {
      final r = Recurrence(
          id: 'r', description: 'x', amount: 1, accountId: 'a', frequency: Frequency.custom, intervalDays: 10,
          startDate: DateTime(2026, 11, 1), endDate: DateTime(2026, 11, 25));
      expect(r.occurrences(DateTime(2026, 10, 1), DateTime(2027, 1, 1)),
          [DateTime(2026, 11, 1), DateTime(2026, 11, 11), DateTime(2026, 11, 21)]);
    });
  });

  group('Ingresos recurrentes', () {
    test('Aparecen como previstos y no cambian el saldo real', () {
      weekly400();
      final ev = l.eventsBetween(DateTime(2026, 11, 1), DateTime(2026, 12, 31)).where((e) => e.isIncome).toList();
      expect(ev.length, 5);
      expect(ev.every((e) => e.statusLabel == 'Previsto'), isTrue);
      expect(l.totalAvailable, 0);
      expect(l.nextIncome?.date, DateTime(2026, 11, 28));
    });

    test('Confirmar una ocurrencia: suma una vez y no se duplica', () {
      final r = weekly400();
      final id = l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 11, 28));
      l.confirmScheduledItem(id);
      expect(l.physicalTotal, 40000);
      // La misma ocurrencia ya no se puede volver a materializar ni confirmar.
      expect(l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 11, 28)), id);
      expect(() => l.confirmScheduledItem(id), throwsA(isA<FinanceException>()));
      final nov28 = l.eventsBetween(DateTime(2026, 11, 28), DateTime(2026, 11, 28));
      expect(nov28.length, 1);
      expect(nov28.single.done, isTrue);
      expect(nov28.single.statusLabel, 'Recibido');
      expect(l.nextIncome?.date, DateTime(2026, 12, 5));
    });

    test('Confirmar con importe distinto al previsto', () {
      final r = weekly400();
      final id = l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 11, 28));
      l.confirmScheduledItem(id, actualAmount: 35000, accountId: bank);
      expect(l.digitalTotal, 35000);
      expect(l.physicalTotal, 0);
    });

    test('No recibido: sale de la agenda y de la proyección; se puede restaurar', () {
      final r = weekly400();
      final id = l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 11, 28));
      l.markScheduledSkipped(id);
      expect(l.agenda().any((e) => e.scheduledItemId == id), isFalse);
      expect(l.totalAvailable, 0);
      l.restoreScheduled(id);
      expect(l.agenda().any((e) => e.scheduledItemId == id), isTrue);
    });

    test('Editar la regla cambia lo futuro, no lo ya confirmado', () {
      final r = weekly400();
      final id = l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 11, 28));
      l.confirmScheduledItem(id);
      l.updateRecurrence(r.id, amount: 50000);
      final ev = l.eventsBetween(DateTime(2026, 11, 28), DateTime(2026, 12, 5));
      expect(ev.first.amount, 40000); // confirmado
      expect(ev.last.amount, 50000); // futuro
      expect(l.physicalTotal, 40000);
    });

    test('Ajustar una sola ocurrencia', () {
      final r = weekly400();
      final id = l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 12, 5));
      l.updateScheduledItem(id, amount: 10000, date: DateTime(2026, 12, 4));
      final ev = l.eventsBetween(DateTime(2026, 12, 1), DateTime(2026, 12, 7));
      expect(ev.length, 1);
      expect(ev.single.date, DateTime(2026, 12, 4));
      expect(ev.single.amount, 10000);
    });

    test('Pausar y eliminar una regla conserva los movimientos reales', () {
      final r = weekly400();
      l.confirmScheduledItem(l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 11, 28)));
      l.setRecurrenceActive(r.id, false);
      expect(l.agenda().where((e) => e.isIncome), isEmpty);
      l.setRecurrenceActive(r.id, true);
      l.deleteRecurrence(r.id);
      expect(l.agenda().where((e) => e.isIncome), isEmpty);
      expect(l.physicalTotal, 40000);
      // El previsto confirmado sigue existiendo, ya sin regla.
      expect(l.scheduledItems.single.recurrenceId, isNull);
      expect(() => Ledger.fromJson(l.toJson()), returnsNormally);
    });

    test('Borrar el movimiento confirmado vuelve a dejar el ingreso como previsto', () {
      final r = weekly400();
      final t = l.confirmScheduledItem(l.ensureScheduledItem(recurrenceId: r.id, occurrenceDate: DateTime(2026, 11, 28)));
      l.deleteTransaction(t.id);
      expect(l.totalAvailable, 0);
      expect(l.eventsBetween(DateTime(2026, 11, 28), DateTime(2026, 11, 28)).single.statusLabel, 'Previsto');
    });

    test('Ocurrencias atrasadas: se muestran pero no se suman a la proyección', () {
      l.addRecurrence(
          description: 'Semanal', amount: 40000, accountId: cash, frequency: Frequency.weekly, startDate: DateTime(2026, 11, 21));
      final p = l.projection(days: 7);
      expect(p.first.event.overdue, isTrue);
      expect(p.first.counted, isFalse);
      expect(p.first.balance, 0);
      expect(p[1].balance, 40000); // sábado 28
    });
  });

  group('Calendario y proyección', () {
    test('Cuotas pagadas y pendientes aparecen una sola vez, con su estado', () {
      l.setBalance(accountId: cash, newBalance: 100000);
      final d = l.addDebt(name: 'DiDi', total: 139200, startDate: now, installments: [
        (amount: 75000, dueDate: DateTime(2026, 12, 1)),
        (amount: 64200, dueDate: DateTime(2026, 12, 16)),
      ]);
      final first = l.installmentsOf(d.id).first;
      l.payInstallment(installmentId: first.id, accountId: cash);
      final ev = l.eventsBetween(DateTime(2026, 12, 1), DateTime(2026, 12, 31));
      expect(ev.length, 2);
      expect(ev.first.done, isTrue);
      expect(ev.first.statusLabel, 'Pagado');
      expect(ev.last.isOpen, isTrue);
    });

    test('Gasto previsto: resta en la proyección; al pagarlo baja el saldo real', () {
      l.setBalance(accountId: cash, newBalance: 50000);
      final s = l.addScheduledItem(accountId: cash, amount: 20000, date: DateTime(2026, 12, 2), description: 'Renta', isIncome: false);
      expect(l.projection().single.balance, 30000);
      expect(l.totalAvailable, 50000);
      l.confirmScheduledItem(s.id);
      expect(l.totalAvailable, 30000);
      expect(l.transactions.last.type, TxType.expense);
      expect(l.upcomingPayments(), isEmpty);
    });

    test('Proyección del ejemplo de la especificación', () {
      l.setBalance(accountId: cash, newBalance: 50000);
      weekly400();
      l.addDebt(name: 'DiDi', total: 75000, startDate: now, installments: [(amount: 75000, dueDate: DateTime(2026, 12, 1))]);
      final p = l.projection(days: 10);
      expect([for (final x in p) x.balance], [90000, 15000, 55000]);
      expect(l.totalAvailable, 50000); // la proyección no modifica la realidad
    });

    test('Pagos del mes incluyen cuotas y gastos programados', () {
      l.setBalance(accountId: bank, newBalance: 100000);
      final d = l.addDebt(name: 'DiDi', total: 75000, startDate: now, installments: [(amount: 75000, dueDate: DateTime(2026, 12, 1))]);
      l.addRecurrence(
          description: 'Internet', amount: 39900, accountId: bank, frequency: Frequency.monthly,
          startDate: DateTime(2026, 12, 10), isIncome: false);
      final dec = DateTime(2026, 12);
      expect(l.scheduledPaymentsInMonth(dec), 114900);
      l.payInstallment(installmentId: l.installmentsOf(d.id).single.id, accountId: bank);
      expect(l.scheduledPaymentsInMonth(dec), 114900);
      expect(l.pendingPaymentsInMonth(dec), 39900);
    });

    test('Alerta de saldo negativo proyectado', () {
      l.addDebt(name: 'DiDi', total: 75000, startDate: now, installments: [(amount: 75000, dueDate: DateTime(2026, 12, 20))]);
      expect(l.alerts.any((a) => a.contains('Según la proyección')), isTrue);
    });

    test('Compatibilidad con respaldos de la v0.2 (scheduledIncomes)', () {
      final s = l.addScheduledIncome(accountId: cash, amount: 40000, date: DateTime(2026, 11, 28));
      final json = l.toJson();
      json['scheduledIncomes'] = json.remove('scheduledItems');
      json.remove('recurrences');
      final restored = Ledger.fromJson(jsonDecode(jsonEncode(json)));
      expect(restored.scheduledItem(s.id).isIncome, isTrue);
      expect(restored.nextIncome?.amount, 40000);
    });
  });
}
