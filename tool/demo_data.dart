// Genera datos de ejemplo (los de la especificación) como JSON.
// Uso: dart run tool/demo_data.dart > demo.json
import 'dart:convert';
import 'dart:io';

import 'package:drago/domain/ledger.dart';
import 'package:drago/domain/models.dart';

void main() {
  final l = Ledger.withDefaults();
  final cash = l.accounts.firstWhere((a) => a.kind == AccountKind.physical).id;
  final bank = l.accounts.firstWhere((a) => a.kind == AccountKind.digital).id;
  final t = l.today;
  l.setBalance(accountId: cash, newBalance: 50000, note: 'Saldo inicial');
  l.setBalance(accountId: bank, newBalance: 15000, note: 'Saldo inicial');
  l.addExpense(accountId: cash, amount: 8000, date: t, description: 'Comida', category: 'Comida');
  // Ingreso semanal de $400 cada sábado y $100 adicionales los martes.
  final sat = t.add(Duration(days: (DateTime.saturday - t.weekday) % 7));
  final tue = t.add(Duration(days: (DateTime.tuesday - t.weekday) % 7));
  l.addRecurrence(description: 'Ingreso semanal', amount: 40000, accountId: cash, frequency: Frequency.weekly, startDate: sat);
  l.addRecurrence(description: 'Ingreso adicional', amount: 10000, accountId: cash, frequency: Frequency.weekly, startDate: tue);
  l.addRecurrence(
      description: 'Internet', amount: 39900, accountId: bank, frequency: Frequency.monthly,
      startDate: DateTime(t.year, t.month, 10), isIncome: false);
  l.addDebt(name: 'DiDi Préstamos', total: 650000, startDate: t, installments: [
    (amount: 75000, dueDate: DateTime(t.year, t.month, t.day + 6)),
    (amount: 64200, dueDate: DateTime(t.year, t.month, t.day + 21)),
    (amount: 12000, dueDate: DateTime(t.year, t.month, t.day + 37)),
    (amount: 12300, dueDate: DateTime(t.year, t.month, t.day + 54)),
  ]);
  l.addDebt(name: 'Coppel audífonos', total: 14400, startDate: t, installments: [
    (amount: 7200, dueDate: DateTime(t.year, t.month, t.day + 11)),
    (amount: 7200, dueDate: DateTime(t.year, t.month, t.day + 41)),
  ]);
  if (const bool.fromEnvironment('enrich') || Platform.environment['ENRICH'] == '1') {
    final didi = l.debts.first;
    final first = l.installmentsOf(didi.id).first;
    l.payInstallment(installmentId: first.id, accountId: cash, amount: 30000);
    final rec = l.recurrences.first;
    final occ = rec.occurrences(t, t.add(const Duration(days: 14)));
    l.confirmScheduledItem(l.ensureScheduledItem(recurrenceId: rec.id, occurrenceDate: occ[0]));
    l.markScheduledSkipped(l.ensureScheduledItem(recurrenceId: rec.id, occurrenceDate: occ[1]));
    l.transfer(fromAccountId: cash, toAccountId: bank, amount: 5000, date: t);
  }
  stdout.writeln(jsonEncode(l.toJson()));
}
