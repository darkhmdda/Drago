import 'package:drago/domain/ledger.dart';
import 'package:drago/domain/statement_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 25);

  group('Lectura de capturas', () {
    test('Estilo DiDi: fecha y monto en líneas separadas', () {
      const text = '''
DiDi Préstamos
Próximos pagos
1 dic
\$763.31
16 dic
\$713.39
Saldo pendiente
\$5,980.10
''';
      final s = parseStatement(text, today: today);
      expect(s.institution, 'DiDi');
      expect(s.payments.map((p) => (p.date, p.amount)), [(DateTime(2026, 12, 1), 76331), (DateTime(2026, 12, 16), 71339)]);
      expect(s.totalPending, 598010);
    });

    test('Estilo tabla: fecha e importe en la misma línea, con año', () {
      const text = 'Coppel\nPago 1   06/12/2026   \$72.00\nPago 2   06/01/2027   \$72.00\nTotal a pagar \$144.00';
      final s = parseStatement(text, today: today);
      expect(s.institution, 'Coppel');
      expect(s.payments.length, 2);
      expect(s.payments.last.date, DateTime(2027, 1, 6));
      expect(s.totalPending, 14400);
    });

    test('Mes escrito completo y año siguiente inferido', () {
      final s = parseStatement('Mercado Pago\nVence el 5 de enero\n1,250.50 MXN', today: today);
      expect(s.institution, 'Mercado Pago');
      expect(s.payments.single.date, DateTime(2027, 1, 5));
      expect(s.payments.single.amount, 125050);
    });

    test('No confunde números de día o folios con importes', () {
      final s = parseStatement('Folio 123456\n1 dic\nCuota 3 de 12\n\$750.00', today: today);
      expect(s.payments.single.amount, 75000);
    });

    test('Texto real del usuario: fechas «16/dic/2026», «2 de 6» y tres deudas en un solo texto', () {
      const text = '''Imagen 1
Detalle de las mensualidades (A pagar)
 * 2 de 6 — Vence el 16/dic/2026: \$ 21.12
 * 3 de 6 — Vence el 18/ene/2027: \$ 21.12
 * 4 de 6 — Vence el 16/feb/2027: \$ 21.12
 * 5 de 6 — Vence el 16/mar/2027: \$ 21.12
 * 6 de 6 — Vence el 16/abr/2027: \$ 21.12
Imagen 2
Detalle de las mensualidades (A pagar)
 * 3 de 6 — Vence el 16/feb/2027: \$ 4.46
 * 4 de 6 — Vence el 16/mar/2027: \$ 4.46
 * 5 de 6 — Vence el 16/abr/2027: \$ 4.46
 * 6 de 6 — Vence el 17/may/2027: \$ 4.46
Imagen 3
Detalle de las mensualidades (A pagar)
 * 4 de 6 — Vence el 16/dic/2026: \$ 301.41
 * 5 de 6 — Vence el 18/ene/2027: \$ 301.41
 * 6 de 6 — Vence el 16/feb/2027: \$ 301.41''';
      final s = parseStatement(text, today: today);
      expect(s.groups.length, 3);
      expect(s.groups.map((g) => g.length), [5, 4, 3]);
      final g1 = s.groups[0];
      expect(g1.first.date, DateTime(2026, 12, 16));
      expect(g1.first.amount, 2112);
      expect(g1.first.number, 2);
      expect(g1.first.of, 6);
      expect(g1.last.date, DateTime(2027, 4, 16));
      expect(s.groups[1].last.date, DateTime(2027, 5, 17));
      expect(s.groups[1].first.amount, 446);
      expect(s.groups[2].map((p) => p.amount).toSet(), {30141});
    });

    test('Otros formatos de fecha: 16-dic-26 y «16 de diciembre del 2026»', () {
      final a = parseStatement('Pago 16-dic-26 \$100.00', today: today);
      expect(a.payments.single.date, DateTime(2026, 12, 16));
      final b = parseStatement('Vence el 16 de diciembre del 2026\n\$250.00', today: today);
      expect(b.payments.single.date, DateTime(2026, 12, 16));
    });

    test('Texto sin pagos', () {
      expect(parseStatement('Hola mundo', today: today).isEmpty, isTrue);
    });
  });

  group('Comparación con los registros', () {
    late Ledger l;
    setUp(() {
      l = Ledger.withDefaults(clock: () => DateTime(2026, 11, 25, 10));
      l.addDebt(name: 'DiDi Préstamos', total: 650000, startDate: today, installments: [
        (amount: 79639, dueDate: DateTime(2026, 12, 1)),
        (amount: 67447, dueDate: DateTime(2026, 12, 16)),
        (amount: 12000, dueDate: DateTime(2027, 1, 1)),
      ]);
    });

    test('Ejemplo de la especificación: antes vs. detectado', () {
      final s = parseStatement('DiDi\n1 dic\n\$763.31\n16 dic\n\$713.39\n1 ene\n\$120.00\n18 ene\n\$123.00', today: today);
      final d = matchDebt(l, s)!;
      expect(d.name, 'DiDi Préstamos');
      final c = compareWithDebt(l, d, s);
      expect(c.map((x) => x.kind), [ChangeKind.update, ChangeKind.update, ChangeKind.unchanged, ChangeKind.newInstallment]);
      expect(c.first.before, 79639);
      expect(c.first.detected.amount, 76331);
    });

    test('Nada cambia hasta aplicar; al aplicar solo lo elegido', () {
      final s = parseStatement('DiDi\n1 dic\n\$763.31\n16 dic\n\$713.39', today: today);
      final d = matchDebt(l, s)!;
      final c = compareWithDebt(l, d, s);
      expect(l.installmentsOf(d.id).first.amount, 79639);
      applyChanges(l, d, [c.first]); // solo la primera
      expect(l.installmentsOf(d.id).map((i) => i.amount), [76331, 67447, 12000]);
    });

    test('Sin fecha cercana, se empareja por número de cuota', () {
      final s = parseStatement('Coppel\n3 de 6 — Vence el 20/ene/2027: \$130.00', today: today);
      final c = compareWithDebt(l, l.debts.single, s);
      expect(c.single.kind, ChangeKind.update);
      expect(c.single.installment!.number, 3);
    });

    test('Cuotas pagadas no se tocan', () {
      final cash = l.accounts.first.id;
      l.setBalance(accountId: cash, newBalance: 100000);
      final first = l.installmentsOf(l.debts.single.id).first;
      l.payInstallment(installmentId: first.id, accountId: cash);
      final s = parseStatement('DiDi\n1 dic\n\$763.31', today: today);
      final c = compareWithDebt(l, l.debts.single, s);
      expect(c.single.kind, ChangeKind.alreadyPaid); // no se vuelve a proponer ni se modifica
    });
  });
}
