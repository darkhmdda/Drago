import 'package:drago/data/widget_service.dart';
import 'package:drago/domain/ledger.dart';
import 'package:drago/ui/themes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Datos del widget: pendientes, enlaces, colores y ocultar importes', () {
    final now = DateTime(2026, 11, 25, 10);
    final l = Ledger.withDefaults(clock: () => now);
    final d = l.addDebt(name: 'Att unefon', total: 88000, startDate: now, monthlyPayment: 44000, paymentDay: 23);
    final data = buildWidgetData(l, AppTheme.nami.data, hideAmounts: true);
    expect(data['hide'], isTrue);
    final events = data['events'] as List;
    expect(events.length, 2);
    expect(events.first['d'], '2026-12-23');
    expect(events.first['t'], 'Att unefon #1');
    expect(events.first['k'], 'e');
    expect(events.first['u'], 'drago://debt?id=${d.id}&date=2026-12-23');
    expect((data['colors'] as Map).keys, containsAll(['bg', 'text', 'primary', 'income', 'expense', 'pending']));
  });
}
