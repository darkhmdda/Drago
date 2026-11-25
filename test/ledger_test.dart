import 'dart:convert';

import 'package:drago/data/app_state.dart';
import 'package:drago/data/storage.dart';
import 'package:drago/domain/ledger.dart';
import 'package:drago/domain/models.dart';
import 'package:drago/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Ledger l;
  late String cash;
  late String bank;
  final now = DateTime(2026, 11, 25, 10);

  setUp(() {
    l = Ledger.withDefaults(clock: () => now);
    cash = l.accounts.firstWhere((a) => a.kind == AccountKind.physical).id;
    bank = l.accounts.firstWhere((a) => a.kind == AccountKind.digital).id;
  });

  group('Pruebas de la especificación (sección 15)', () {
    test('Físico \$200 + digital \$150 = total \$350', () {
      l.setBalance(accountId: cash, newBalance: 20000);
      l.setBalance(accountId: bank, newBalance: 15000);
      expect(l.physicalTotal, 20000);
      expect(l.digitalTotal, 15000);
      expect(l.totalAvailable, 35000);
    });

    test('Gasto de \$80 en efectivo: físico baja \$80', () {
      l.setBalance(accountId: cash, newBalance: 50000);
      l.addExpense(accountId: cash, amount: 8000, date: now, description: 'Comida');
      expect(l.physicalTotal, 42000);
      expect(l.digitalTotal, 0);
    });

    test('Transferencia de \$100: el total no cambia', () {
      l.setBalance(accountId: cash, newBalance: 50000);
      l.transfer(fromAccountId: cash, toAccountId: bank, amount: 10000, date: now);
      expect(l.physicalTotal, 40000);
      expect(l.digitalTotal, 10000);
      expect(l.totalAvailable, 50000);
      final m = l.monthSummary(now);
      expect(m.income, 0);
      expect(m.expenses, 0);
    });

    test('Ingreso previsto de \$400: el saldo real no cambia; al confirmarlo sube \$400', () {
      l.setBalance(accountId: cash, newBalance: 50000);
      final s = l.addScheduledIncome(accountId: cash, amount: 40000, date: DateTime(2026, 11, 28));
      expect(l.totalAvailable, 50000);
      expect(l.nextIncome?.scheduledItemId, s.id);
      l.confirmScheduledIncome(s.id);
      expect(l.totalAvailable, 90000);
      expect(() => l.confirmScheduledIncome(s.id), throwsA(isA<FinanceException>()));
      expect(l.totalAvailable, 90000);
    });

    test('Cuotas variables conservan cada importe y fecha', () {
      final d = _didi(l);
      final insts = l.installmentsOf(d.id);
      expect(insts.map((i) => i.amount), [75000, 64200, 12000, 12300]);
      expect(insts.map((i) => i.number), [1, 2, 3, 4]);
      expect(insts.first.dueDate, DateTime(2026, 12, 1));
    });

    test('Marcar cuota como pagada descuenta una sola vez', () {
      l.setBalance(accountId: cash, newBalance: 100000);
      final d = _didi(l);
      final first = l.installmentsOf(d.id).first;
      l.payInstallment(installmentId: first.id, accountId: cash, date: DateTime(2026, 11, 30));
      expect(l.physicalTotal, 25000);
      expect(() => l.payInstallment(installmentId: first.id, accountId: cash), throwsA(isA<FinanceException>()));
      expect(l.physicalTotal, 25000);
      final s = l.summaryOf(d.id);
      expect(s.original, 650000);
      expect(s.paid, 75000);
      expect(s.remaining, 575000);
      expect(l.installmentStatus(first), InstallmentStatus.paid);
    });

    test('Cambiar fecha de cuota actualiza la agenda', () {
      final d = _didi(l);
      final first = l.installmentsOf(d.id).first;
      l.updateInstallment(first.id, dueDate: DateTime(2026, 12, 3));
      final item = l.agenda().firstWhere((a) => a.installmentId == first.id);
      expect(item.date, DateTime(2026, 12, 3));
      expect(l.agenda().where((a) => a.installmentId == first.id).length, 1);
      expect(l.auditLog.last.details, contains('01/12/2026 → 03/12/2026'));
    });

    test('Pagar cuota la quita de la agenda (no genera más recordatorios)', () {
      l.setBalance(accountId: cash, newBalance: 100000);
      final d = _didi(l);
      final first = l.installmentsOf(d.id).first;
      expect(l.agenda().any((a) => a.installmentId == first.id), isTrue);
      l.payInstallment(installmentId: first.id, accountId: cash);
      expect(l.agenda().any((a) => a.installmentId == first.id), isFalse);
      expect(l.nextPayment?.number, 2);
    });

    test('Cerrar y abrir: la información persiste', () async {
      final storage = MemoryLedgerStorage();
      final state = await AppState.open(storage);
      final c = state.ledger.accounts.first.id;
      await state.run((x) => x.setBalance(accountId: c, newBalance: 12345));
      await state.run((x) => _didi(x));
      final reopened = await AppState.open(storage);
      expect(reopened.ledger.balance(c), 12345);
      expect(reopened.ledger.debts.single.name, 'DiDi Préstamos');
      expect(reopened.ledger.installments.length, 4);
    });
  });

  group('Reglas adicionales', () {
    test('Abonos parciales: 300 + 450 completan una cuota de 750', () {
      l.setBalance(accountId: cash, newBalance: 100000);
      final d = _didi(l);
      final first = l.installmentsOf(d.id).first;
      l.payInstallment(installmentId: first.id, accountId: cash, amount: 30000);
      expect(l.installmentStatus(first), InstallmentStatus.partial);
      expect(() => l.payInstallment(installmentId: first.id, accountId: cash, amount: 50000),
          throwsA(isA<FinanceException>()));
      l.payInstallment(installmentId: first.id, accountId: cash, amount: 45000);
      expect(l.installmentStatus(first), InstallmentStatus.paid);
      expect(l.paymentsForInstallment(first.id).length, 2);
      expect(l.physicalTotal, 25000);
    });

    test('El monto original y la suma de cuotas pueden no coincidir', () {
      final d = _didi(l); // 6500 vs 1635 en cuotas
      final s = l.summaryOf(d.id);
      expect(s.remaining, 650000);
      expect(s.pendingInstallments, 163500);
      expect(s.hasMismatch, isTrue);
    });

    test('Pagar todas las cuotas liquida la deuda; borrar un pago la reactiva', () {
      l.setBalance(accountId: bank, newBalance: 500000);
      final d = l.addDebt(name: 'Coppel', total: 14400, startDate: now, installments: [
        (amount: 7200, dueDate: DateTime(2026, 12, 6)),
        (amount: 7200, dueDate: DateTime(2027, 1, 6)),
      ]);
      Transaction? last;
      for (final i in l.installmentsOf(d.id)) {
        last = l.payInstallment(installmentId: i.id, accountId: bank);
      }
      expect(l.debt(d.id).status, DebtStatus.settled);
      l.deleteTransaction(last!.id);
      expect(l.debt(d.id).status, DebtStatus.active);
      expect(l.digitalTotal, 500000 - 7200);
    });

    test('Cuota vencida', () {
      final d = l.addDebt(name: 'X', total: 1000, startDate: DateTime(2026, 11, 1), installments: [
        (amount: 1000, dueDate: DateTime(2026, 11, 20)),
      ]);
      expect(l.installmentStatus(l.installmentsOf(d.id).first), InstallmentStatus.overdue);
      expect(l.alerts.first, contains('vencida'));
    });

    test('Corrección de saldo queda registrada como ajuste', () {
      l.setBalance(accountId: cash, newBalance: 50000);
      l.addExpense(accountId: cash, amount: 8000, date: now);
      l.setBalance(accountId: cash, newBalance: 40000, note: 'Conteo real');
      expect(l.physicalTotal, 40000);
      final adj = l.transactions.where((t) => t.type == TxType.adjustment).toList();
      expect(adj.last.amount, -2000);
      expect(l.auditLog.any((a) => a.action == 'Corrección de saldo'), isTrue);
    });

    test('Una operación fallida no modifica nada (atomicidad)', () async {
      final state = await AppState.open(MemoryLedgerStorage());
      final before = jsonEncode(state.ledger.toJson());
      await expectLater(
          state.run((x) => x.transfer(fromAccountId: 'a', toAccountId: 'b', amount: 100, date: now)),
          throwsA(isA<FinanceException>()));
      expect(jsonEncode(state.ledger.toJson()), before);
    });

    test('Respaldo: exportar y restaurar', () async {
      final state = await AppState.open(MemoryLedgerStorage());
      final c = state.ledger.accounts.first.id;
      await state.run((x) => x.setBalance(accountId: c, newBalance: 777));
      final backup = state.exportBackup();
      final other = await AppState.open(MemoryLedgerStorage());
      await other.restoreBackup(backup);
      expect(other.ledger.balance(c), 777);
      await expectLater(other.restoreBackup('no es json'), throwsA(isA<FinanceException>()));
    });
  });

  group('Dinero', () {
    test('parseMoney evita punto flotante', () {
      expect(parseMoney('500'), 50000);
      expect(parseMoney('\$1,234.56'), 123456);
      expect(parseMoney('0.1'), 10);
      expect(parseMoney('642.'), 64200);
      expect(parseMoney('abc'), isNull);
      expect(parseMoney('1.234'), isNull);
    });
    test('formatMoney', () {
      expect(formatMoney(650000), '\$6,500.00');
      expect(formatMoney(-8000), '-\$80.00');
      expect(formatMoney(40000, signed: true), '+\$400.00');
      expect(formatMoney(5), '\$0.05');
    });
  });
}

Debt _didi(Ledger l) => l.addDebt(
      name: 'DiDi Préstamos',
      total: 650000,
      startDate: DateTime(2026, 11, 20),
      installments: [
        (amount: 64200, dueDate: DateTime(2026, 12, 16)),
        (amount: 75000, dueDate: DateTime(2026, 12, 1)),
        (amount: 12000, dueDate: DateTime(2027, 1, 1)),
        (amount: 12300, dueDate: DateTime(2027, 1, 18)),
      ],
    );
