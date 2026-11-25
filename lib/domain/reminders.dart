import 'package:intl/intl.dart';

import 'ledger.dart';
import 'money.dart';

/// Preferencias de recordatorios (se guardan por dispositivo).
class ReminderSettings {
  final bool enabled;

  /// Días de anticipación. 0 = el día del vencimiento.
  final List<int> daysBefore;
  final int hour;
  final int minute;

  /// Recordar el día que se espera un ingreso, para confirmarlo.
  final bool incomeReminders;

  const ReminderSettings({
    this.enabled = true,
    this.daysBefore = const [7, 2, 1, 0],
    this.hour = 9,
    this.minute = 0,
    this.incomeReminders = true,
  });

  ReminderSettings copyWith({bool? enabled, List<int>? daysBefore, int? hour, int? minute, bool? incomeReminders}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        daysBefore: daysBefore ?? this.daysBefore,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        incomeReminders: incomeReminders ?? this.incomeReminders,
      );

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'daysBefore': daysBefore, 'hour': hour, 'minute': minute, 'incomeReminders': incomeReminders};

  factory ReminderSettings.fromJson(Map<String, dynamic> j) => ReminderSettings(
        enabled: j['enabled'] ?? true,
        daysBefore: ((j['daysBefore'] as List?) ?? const [7, 2, 1, 0]).map((e) => (e as num).toInt()).toList(),
        hour: j['hour'] ?? 9,
        minute: j['minute'] ?? 0,
        incomeReminders: j['incomeReminders'] ?? true,
      );
}

/// Un recordatorio concreto: un evento (cuota, gasto o ingreso previsto) y
/// cuántos días antes avisa.
class Reminder {
  final CalendarEvent event;
  final int daysBefore;
  final DateTime fireAt;
  final String title;
  final String body;

  const Reminder({required this.event, required this.daysBefore, required this.fireAt, required this.title, required this.body});

  /// Clave estable: el mismo evento y anticipación siempre dan la misma clave,
  /// así nunca se duplican y se pueden cancelar al pagar.
  String get key => '${event.key}|$daysBefore';

  /// Id numérico estable (31 bits) para el sistema de notificaciones.
  int get id => stableId(key);
}

/// FNV-1a de 32 bits, reducido a 31 bits positivos.
int stableId(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

final _dayFmt = DateFormat("d 'de' MMMM", 'es_MX');

String _when(int days) => switch (days) {
      0 => 'hoy',
      1 => 'mañana',
      _ => 'en $days días',
    };

/// Genera los recordatorios de los eventos pendientes.
///
/// - Solo eventos abiertos: lo pagado o recibido deja de recordarse.
/// - Si cambia la fecha o el importe, el recordatorio cambia con él.
List<Reminder> buildReminders(Ledger l, ReminderSettings s, {int horizonDays = 60}) {
  if (!s.enabled) return const [];
  final out = <Reminder>[];
  final offsets = s.daysBefore.toSet().toList()..sort((a, b) => b.compareTo(a));
  for (final e in l.agenda(days: horizonDays)) {
    if (!e.isOpen) continue;
    if (e.isIncome) {
      if (!s.incomeReminders) continue;
      out.add(Reminder(
        event: e,
        daysBefore: 0,
        fireAt: DateTime(e.date.year, e.date.month, e.date.day, s.hour, s.minute),
        title: 'Ingreso previsto: ${e.title}',
        body: 'Hoy esperas ${formatMoney(e.amount)} MXN. Cuando lo recibas, confírmalo en Drago para sumarlo a tu saldo.',
      ));
      continue;
    }
    for (final d in offsets) {
      final day = DateTime(e.date.year, e.date.month, e.date.day - d);
      out.add(Reminder(
        event: e,
        daysBefore: d,
        fireAt: DateTime(day.year, day.month, day.day, s.hour, s.minute),
        title: d == 0 ? 'Hoy vence: ${e.title}' : 'Pago próximo: ${e.title}',
        body: 'Tienes un pago ${d == 0 ? 'que vence hoy' : 'próximo'} de ${formatMoney(e.amount)} MXN correspondiente a '
            '${e.title}. Fecha límite: ${_dayFmt.format(e.date)} (${_when(d)}).'
            '${d >= 2 ? ' Te recomendamos realizarlo uno o dos días antes del vencimiento.' : ''}',
      ));
    }
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out;
}

/// Recordatorios que ya deberían haberse mostrado (para el centro de
/// notificaciones dentro de la app): solo el más reciente de cada evento.
List<Reminder> dueReminders(Ledger l, ReminderSettings s, DateTime now) {
  final latest = <String, Reminder>{};
  for (final r in buildReminders(l, s)) {
    if (r.fireAt.isAfter(now)) continue;
    final prev = latest[r.event.key];
    if (prev == null || r.fireAt.isAfter(prev.fireAt)) latest[r.event.key] = r;
  }
  return latest.values.toList()..sort((a, b) => b.fireAt.compareTo(a.fireAt));
}

/// Recordatorios futuros a programar en el sistema (los más cercanos primero).
List<Reminder> upcomingReminders(Ledger l, ReminderSettings s, DateTime now, {int limit = 60}) =>
    buildReminders(l, s).where((r) => r.fireAt.isAfter(now)).take(limit).toList();
