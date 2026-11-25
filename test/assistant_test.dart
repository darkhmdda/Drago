import 'dart:convert';

import 'package:drago/domain/assistant.dart';
import 'package:drago/domain/ledger.dart';
import 'package:drago/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late Ledger l;
  late String cash;
  late String bank;
  final now = DateTime(2026, 11, 25, 10);

  setUpAll(() => initializeDateFormatting('es_MX'));
  setUp(() {
    l = Ledger.withDefaults(clock: () => now);
    cash = l.accounts.firstWhere((a) => a.kind == AccountKind.physical).id;
    bank = l.accounts.firstWhere((a) => a.kind == AccountKind.digital).id;
    l.setBalance(accountId: cash, newBalance: 50000);
    l.addRecurrence(description: 'Ingreso semanal', amount: 40000, accountId: cash, frequency: Frequency.weekly,
        startDate: DateTime(2026, 11, 28));
    l.addDebt(name: 'DiDi Préstamos', total: 650000, startDate: now, installments: [
      (amount: 75000, dueDate: DateTime(2026, 12, 1)),
      (amount: 64200, dueDate: DateTime(2026, 12, 16)),
    ]);
    l.addDebt(name: 'Coppel audífonos', total: 14400, startDate: now, installments: [
      (amount: 7200, dueDate: DateTime(2026, 12, 6)),
    ]);
  });

  /// Aplica una propuesta como lo haría el botón «Confirmar».
  String confirm(AssistantReply r) {
    expect(r, isA<ProposalReply>(), reason: r is AnswerReply ? r.text : '$r');
    final p = r as ProposalReply;
    p.apply(l);
    return p.done(l);
  }

  test('«Tengo 500» actualiza el dinero físico', () {
    l.addExpense(accountId: cash, amount: 1000, date: now);
    final r = interpret('Tengo 500', l);
    expect((r as ProposalReply).details.first, contains('Dinero físico'));
    confirm(r);
    expect(l.physicalTotal, 50000);
  });

  test('«Digital tengo 150» actualiza el dinero digital', () {
    confirm(interpret('Digital tengo 150', l));
    expect(l.digitalTotal, 15000);
    expect(l.physicalTotal, 50000);
  });

  test('«Hoy gasté 80 pesos en comida»', () {
    final r = interpret('Hoy gasté 80 pesos en comida', l) as ProposalReply;
    expect(r.details, contains('Categoría: Comida'));
    final done = confirm(r);
    expect(l.physicalTotal, 42000);
    expect(done, contains('\$420.00'));
  });

  test('Gasto con tarjeta va a la cuenta digital', () {
    l.setBalance(accountId: bank, newBalance: 20000);
    confirm(interpret('Pagué 120 de luz con tarjeta', l));
    expect(l.digitalTotal, 8000);
    expect(l.transactions.last.category, 'Servicios');
  });

  test('«Recibí 400» confirma el ingreso previsto (no crea uno nuevo)', () {
    final r = interpret('Recibí 400', l) as ProposalReply;
    expect(r.title, contains('Ingreso semanal'));
    confirm(r);
    expect(l.physicalTotal, 90000);
    expect(l.nextIncome!.date, DateTime(2026, 12, 5));
  });

  test('Ingreso que no estaba previsto se registra como nuevo', () {
    confirm(interpret('Me pagaron 250', l));
    expect(l.physicalTotal, 75000);
  });

  test('«Pagué los 750 de DiDi» paga la cuota correcta, una sola vez', () {
    final done = confirm(interpret('Pagué los 750 de DiDi', l));
    expect(l.physicalTotal, -25000);
    expect(done, contains('Cuota pagada'));
    // Volver a decirlo no descuenta otra vez la misma cuota.
    final again = interpret('Pagué los 750 de DiDi', l);
    expect(again, isA<AnswerReply>());
  });

  test('«Pagué DiDi» con varias cuotas pendientes pregunta cuál', () {
    final r = interpret('Pagué DiDi', l);
    expect(r, isA<ChoiceReply>());
    expect((r as ChoiceReply).options.length, 2);
    confirm(r.options.last.$2);
    expect(l.paidForInstallment(l.installmentsOf(l.debts.first.id).last.id), 64200);
  });

  test('Abono parcial', () {
    confirm(interpret('Abono 30 a Coppel', l));
    expect(l.remainingForInstallment(l.installmentsOf(l.debts.last.id).single.id), 4200);
    // Más de lo que falta: lo explica en lugar de descontarlo.
    expect((interpret('Abono 300 a Coppel', l) as AnswerReply).text, contains('más de lo que falta'));
  });

  test('«Cambió la cuota de Coppel a 450» muestra antes y después', () {
    final r = interpret('Cambió la cuota de Coppel a 450', l) as ProposalReply;
    expect(r.details.first, contains('\$72.00 → \$450.00'));
    confirm(r);
    expect(l.installmentsOf(l.debts.last.id).single.amount, 45000);
  });

  test('«Cambió la cuota a 650» sin decir la deuda: pregunta cuál', () {
    expect(interpret('Cambió la cuota a 650', l), isA<ChoiceReply>());
  });

  test('«¿Cuánto debo en diciembre?»', () {
    final r = interpret('¿Cuánto debo en diciembre?', l) as AnswerReply;
    expect(r.text, contains('\$1,464.00')); // 750 + 642 + 72
    expect(r.text, contains('DiDi'));
  });

  test('«¿Cuánto tengo?» no incluye ingresos previstos', () {
    final r = interpret('¿Cuánto tengo?', l) as AnswerReply;
    expect(r.text, contains('\$500.00'));
  });

  test('Historial: «¿Cuánto tenía el 20 de noviembre?»', () {
    final r = interpret('¿Cuánto tenía el 20 de noviembre?', l) as AnswerReply;
    expect(r.text, contains('\$0.00')); // el saldo inicial se registró el 25
  });

  test('Transferencias', () {
    confirm(interpret('Pasé 200 al banco', l));
    expect(l.digitalTotal, 20000);
    expect(l.totalAvailable, 50000);
    confirm(interpret('Saqué 50 del banco', l));
    expect(l.digitalTotal, 15000);
  });

  test('«Simula diciembre con 400 semanales» no modifica nada real', () {
    final before = jsonEncode(l.toJson());
    final r = interpret('Simula diciembre con 500 semanales', l);
    expect(r, isA<SimulationReply>());
    expect((r as SimulationReply).text, contains('Tus datos reales no cambiaron'));
    expect(jsonEncode(l.toJson()), before);
    expect(interpret('Cancela esa simulación', l), isA<CancelSimulationReply>());
  });

  test('Simular una semana sin ingresos', () {
    final r = interpret('Simula una semana sin ingresos', l) as SimulationReply;
    expect(r.text, contains('negativo'));
  });

  test('Ayuda y textos no entendidos', () {
    expect((interpret('ayuda', l) as AnswerReply).text, contains('Tengo 500'));
    expect((interpret('blablabla', l) as AnswerReply).text, contains('No entendí'));
  });
}
