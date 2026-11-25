// Genera datos de ejemplo (los de la especificación) como JSON.
// Uso: dart run tool/demo_data.dart > demo.json
import 'dart:convert';
import 'dart:io';

import 'package:finansync/domain/ledger.dart';
import 'package:finansync/domain/models.dart';

void main() {
  final l = Ledger.withDefaults();
  final cash = l.accounts.firstWhere((a) => a.kind == AccountKind.physical).id;
  final bank = l.accounts.firstWhere((a) => a.kind == AccountKind.digital).id;
  final t = l.today;
  l.setBalance(accountId: cash, newBalance: 50000, note: 'Saldo inicial');
  l.setBalance(accountId: bank, newBalance: 15000, note: 'Saldo inicial');
  l.addExpense(accountId: cash, amount: 8000, date: t, description: 'Comida', category: 'Comida');
  l.addScheduledIncome(accountId: cash, amount: 40000, date: t.add(const Duration(days: 3)), description: 'Ingreso semanal');
  l.addScheduledIncome(accountId: cash, amount: 40000, date: t.add(const Duration(days: 10)), description: 'Ingreso semanal');
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
  stdout.writeln(jsonEncode(l.toJson()));
}
