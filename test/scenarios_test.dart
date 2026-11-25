import 'dart:convert';

import 'package:drago/domain/ledger.dart';
import 'package:drago/domain/models.dart';
import 'package:drago/domain/scenarios.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Ledger l;
  late String cash;
  final now = DateTime(2026, 11, 25, 10);

  setUp(() {
    l = Ledger.withDefaults(clock: () => now);
    cash = l.accounts.firstWhere((a) => a.kind == AccountKind.physical).id;
    l.setBalance(accountId: cash, newBalance: 50000);
    l.addRecurrence(description: 'Ingreso semanal', amount: 40000, accountId: cash, frequency: Frequency.weekly,
        startDate: DateTime(2026, 11, 28));
    l.addDebt(name: 'DiDi', total: 139200, startDate: now, installments: [
      (amount: 75000, dueDate: DateTime(2026, 12, 1)),
      (amount: 64200, dueDate: DateTime(2026, 12, 16)),
    ]);
  });

  Scenario sc(List<ScenarioAdjustment> a) => Scenario.create('Prueba', a, now);

  test('La proyección base coincide con el ejemplo de la especificación', () {
    final r = projectBase(l, days: 10);
    expect(r.startBalance, 50000);
    expect(r.daily.first.$2, 50000); // hoy
    expect(r.daily[3].$2, 90000); // sáb 28: +400
    expect(r.daily[6].$2, 15000); // mar 1: -750
    expect(r.daily[10].$2, 55000); // sáb 5: +400
  });

  test('Ingreso semanal de \$500 en vez de \$400', () {
    final rec = l.recurrences.single;
    final r = simulate(l, sc([ScenarioAdjustment(kind: AdjustmentKind.changeRecurrence, recurrenceId: rec.id, amount: 50000)]), days: 10);
    expect(r.daily[3].$2, 100000);
    expect(r.finalBalance, 75000);
  });

  test('Una semana sin ingresos', () {
    final r = simulate(
        l, sc([ScenarioAdjustment(kind: AdjustmentKind.skipIncomes, date: DateTime(2026, 11, 26), endDate: DateTime(2026, 12, 2))]),
        days: 10);
    expect(r.daily[3].$2, 50000);
    expect(r.firstNegative, DateTime(2026, 12, 1)); // 500 - 750
    expect(r.minimum.$2, -25000);
  });

  test('Gasto extraordinario e ingreso extra', () {
    final r = simulate(
        l,
        sc([
          ScenarioAdjustment(kind: AdjustmentKind.expense, amount: 20000, date: DateTime(2026, 11, 26), description: 'Médico'),
          ScenarioAdjustment(kind: AdjustmentKind.income, amount: 10000, date: DateTime(2026, 11, 27)),
        ]),
        days: 3);
    expect(r.daily[1].$2, 30000);
    expect(r.daily[2].$2, 40000);
  });

  test('Adelantar una cuota', () {
    final inst = l.installmentsOf(l.debts.single.id).last; // 16 dic
    final r = simulate(l, sc([ScenarioAdjustment(kind: AdjustmentKind.moveInstallment, installmentId: inst.id, date: DateTime(2026, 12, 2))]),
        days: 10);
    expect(r.daily[7].$2, 15000 - 64200);
  });

  test('Ingreso recurrente hipotético (simula diciembre con 400 semanales)', () {
    final r = simulate(
        l,
        sc([ScenarioAdjustment(kind: AdjustmentKind.income, amount: 40000, frequency: Frequency.weekly, date: DateTime(2026, 12, 1),
            endDate: DateTime(2026, 12, 31))]),
        days: 36);
    expect(r.totalIn, projectBase(l, days: 36).totalIn + 5 * 40000);
  });

  test('Simular NUNCA modifica los datos reales', () {
    final before = jsonEncode(l.toJson());
    simulate(
        l,
        sc([
          ScenarioAdjustment(kind: AdjustmentKind.skipIncomes, date: DateTime(2026, 11, 26), endDate: DateTime(2026, 12, 31)),
          ScenarioAdjustment(kind: AdjustmentKind.changeRecurrence, recurrenceId: l.recurrences.single.id, amount: 1),
          ScenarioAdjustment(kind: AdjustmentKind.moveInstallment, installmentId: l.installments.first.id, date: DateTime(2027, 1, 1)),
        ]));
    expect(jsonEncode(l.toJson()), before);
  });

  test('Guardar, persistir y eliminar simulaciones', () {
    final s = l.saveScenario(sc([const ScenarioAdjustment(kind: AdjustmentKind.expense, amount: 100)]));
    final restored = Ledger.fromJson(jsonDecode(jsonEncode(l.toJson())));
    expect(restored.scenarios.single.adjustments.single.amount, 100);
    l.deleteScenario(s.id);
    expect(l.scenarios, isEmpty);
    expect(() => l.saveScenario(sc(const [])), throwsA(isA<FinanceException>()));
  });

  test('Cambios que ya no aplican se reportan, sin fallar', () {
    final r = simulate(l, sc([const ScenarioAdjustment(kind: AdjustmentKind.moveInstallment, installmentId: 'no-existe')]));
    expect(r.skipped, hasLength(1));
  });
}
