import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';
import 'recurrences_screen.dart';
import 'scheduled_dialogs.dart';

enum CalendarView { month, week, agenda }

/// Calendario financiero: vista mensual, semanal y agenda de próximos eventos.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  var _view = CalendarView.month;
  late DateTime _selected = dayOf(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    return PageBody(children: [
      Row(children: [
        Expanded(
          child: SegmentedButton<CalendarView>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: CalendarView.month, label: Text('Mes')),
              ButtonSegment(value: CalendarView.week, label: Text('Semana')),
              ButtonSegment(value: CalendarView.agenda, label: Text('Agenda')),
            ],
            selected: {_view},
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Ingresos y gastos recurrentes',
          icon: const Icon(Icons.repeat),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurrencesScreen())),
        ),
      ]),
      const SizedBox(height: 8),
      const _Legend(),
      const SizedBox(height: 8),
      switch (_view) {
        CalendarView.month => _MonthView(ledger: l, selected: _selected, onSelect: (d) => setState(() => _selected = d)),
        CalendarView.week => _WeekView(ledger: l, anchor: _selected, onMove: (d) => setState(() => _selected = d)),
        CalendarView.agenda => _AgendaView(ledger: l),
      },
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    const items = [
      (FinColors.income, 'Ingreso'),
      (FinColors.pending, 'Pago pendiente'),
      (FinColors.expense, 'Vencido'),
      (FinColors.paid, 'Pagado'),
      (FinColors.neutral, 'No recibido / cancelado'),
    ];
    return Wrap(spacing: 12, runSpacing: 4, children: [
      for (final (c, t) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(t, style: Theme.of(context).textTheme.bodySmall),
        ]),
    ]);
  }
}

/// Fila de un evento, reutilizada por las tres vistas.
class EventTile extends StatelessWidget {
  final CalendarEvent event;
  final String? extra;
  final bool showDate;
  const EventTile({super.key, required this.event, this.extra, this.showDate = true});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final color = eventColor(e);
    final strike = e.skipped ? TextDecoration.lineThrough : null;
    return Card(
      child: ListTile(
        onTap: () => showEventActions(context, e),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(eventIcon(e), color: color, size: 20)),
        title: Text(e.title, style: TextStyle(decoration: strike)),
        subtitle: Text([
          if (showDate) fmtShortDate(e.date),
          e.statusLabel,
          if (e.recurrenceId != null) 'recurrente',
          ?extra,
        ].join(' · ')),
        trailing: Text(formatMoney(e.signed, signed: true),
            style: TextStyle(color: color, fontWeight: FontWeight.w700, decoration: strike)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista mensual
// ---------------------------------------------------------------------------

class _MonthView extends StatelessWidget {
  final Ledger ledger;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _MonthView({required this.ledger, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(selected.year, selected.month, 1);
    final last = DateTime(selected.year, selected.month + 1, 0);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final gridEnd = last.add(Duration(days: 7 - last.weekday));
    final events = ledger.eventsBetween(gridStart, gridEnd);
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final e in events) {
      byDay.putIfAbsent(e.date, () => []).add(e);
    }
    final today = ledger.today;
    final weeks = (gridEnd.difference(gridStart).inDays + 1) ~/ 7;

    final monthEvents = events.where((e) => e.date.month == selected.month && e.date.year == selected.year && !e.skipped);
    final incomes = monthEvents.where((e) => e.isIncome).fold<int>(0, (s, e) => s + e.amount);
    final payments = monthEvents.where((e) => !e.isIncome).fold<int>(0, (s, e) => s + e.amount);
    final pendingPayments = monthEvents.where((e) => !e.isIncome && e.isOpen).fold<int>(0, (s, e) => s + e.amount);
    final dayEvents = byDay[selected] ?? const [];

    void moveMonth(int delta) {
      final target = DateTime(selected.year, selected.month + delta, 1);
      final day = selected.day.clamp(1, DateTime(target.year, target.month + 1, 0).day);
      onSelect(DateTime(target.year, target.month, day));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(onPressed: () => moveMonth(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Mes anterior'),
        Expanded(
          child: Text(toBeginningOfSentenceCase(DateFormat('MMMM y', 'es_MX').format(first)),
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        IconButton(onPressed: () => moveMonth(1), icon: const Icon(Icons.chevron_right), tooltip: 'Mes siguiente'),
        TextButton(onPressed: () => onSelect(today), child: const Text('Hoy')),
      ]),
      Row(children: [
        for (final d in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
          Expanded(child: Center(child: Text(d, style: theme.textTheme.labelMedium))),
      ]),
      const SizedBox(height: 4),
      LayoutBuilder(builder: (context, c) {
        final cellW = c.maxWidth / 7;
        final roomy = cellW >= 96;
        return Column(children: [
          for (var w = 0; w < weeks; w++)
            Row(children: [
              for (var k = 0; k < 7; k++)
                () {
                  final day = DateTime(gridStart.year, gridStart.month, gridStart.day + w * 7 + k);
                  return Expanded(
                    child: _DayCell(
                      day: day,
                      events: byDay[day] ?? const [],
                      inMonth: day.month == selected.month,
                      isToday: day == today,
                      isSelected: day == selected,
                      roomy: roomy,
                      onTap: () => onSelect(day),
                    ),
                  );
                }(),
            ]),
        ]);
      }),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 24, runSpacing: 8, children: [
            _Stat('Ingresos del mes', formatMoney(incomes), FinColors.income),
            _Stat('Pagos y gastos del mes', formatMoney(payments), FinColors.pending),
            _Stat('Falta pagar', formatMoney(pendingPayments), FinColors.expense),
          ]),
        ),
      ),
      SectionTitle(toBeginningOfSentenceCase(DateFormat("EEEE d 'de' MMMM", 'es_MX').format(selected))),
      if (dayEvents.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('Sin eventos este día.', textAlign: TextAlign.center)),
      for (final e in dayEvents) EventTile(event: e, showDate: false),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ]);
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final List<CalendarEvent> events;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool roomy;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.events,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.roomy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: roomy ? 84 : 52,
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primaryContainer : (inMonth ? scheme.surfaceContainerLow : null),
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        child: Column(crossAxisAlignment: roomy ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
          Text('${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: inMonth ? null : scheme.outline,
              )),
          const SizedBox(height: 2),
          if (roomy)
            for (final e in events.take(3))
              Text(
                '${e.isIncome ? '+' : '-'}${formatMoney(e.amount).replaceAll('.00', '')} ${e.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    color: eventColor(e),
                    fontWeight: FontWeight.w600,
                    decoration: e.skipped ? TextDecoration.lineThrough : null),
              )
          else
            Wrap(spacing: 2, runSpacing: 2, alignment: WrapAlignment.center, children: [
              for (final e in events.take(4))
                Container(width: 6, height: 6, decoration: BoxDecoration(color: eventColor(e), shape: BoxShape.circle)),
            ]),
          if (roomy && events.length > 3) Text('+${events.length - 3} más', style: const TextStyle(fontSize: 10)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista semanal
// ---------------------------------------------------------------------------

class _WeekView extends StatelessWidget {
  final Ledger ledger;
  final DateTime anchor;
  final ValueChanged<DateTime> onMove;
  const _WeekView({required this.ledger, required this.anchor, required this.onMove});

  @override
  Widget build(BuildContext context) {
    final start = anchor.subtract(Duration(days: anchor.weekday - 1));
    final end = start.add(const Duration(days: 6));
    final events = ledger.eventsBetween(start, end);
    final net = events.where((e) => !e.skipped).fold<int>(0, (s, e) => s + e.signed);
    final fmt = DateFormat('d MMM', 'es_MX');
    final today = ledger.today;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(onPressed: () => onMove(anchor.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text('${fmt.format(start)} – ${fmt.format(end)}',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        IconButton(onPressed: () => onMove(anchor.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: () => onMove(today), child: const Text('Hoy')),
      ]),
      Text('Balance previsto de la semana: ${formatMoney(net, signed: true)}',
          textAlign: TextAlign.center, style: TextStyle(color: amountColor(net), fontWeight: FontWeight.w600)),
      for (var k = 0; k < 7; k++)
        () {
          final day = start.add(Duration(days: k));
          final list = events.where((e) => e.date == day).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
              child: Text(
                toBeginningOfSentenceCase(DateFormat("EEEE d", 'es_MX').format(day)) + (day == today ? ' · hoy' : ''),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600, color: day == today ? Theme.of(context).colorScheme.primary : null),
              ),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('Sin eventos', style: Theme.of(context).textTheme.bodySmall),
              ),
            for (final e in list) EventTile(event: e, showDate: false),
          ]);
        }(),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Agenda con proyección
// ---------------------------------------------------------------------------

class _AgendaView extends StatelessWidget {
  final Ledger ledger;
  const _AgendaView({required this.ledger});

  @override
  Widget build(BuildContext context) {
    final points = ledger.projection(days: 90);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Pendientes · próximos 90 días'),
          subtitle: Text('Saldo real hoy: ${formatMoney(ledger.totalAvailable)}. «Proyectado» es solo una estimación '
              'y nunca modifica tus saldos reales. Los ingresos atrasados no se suman hasta que los confirmes.'),
        ),
      ),
      if (points.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No hay eventos pendientes.'))),
      for (final p in points)
        EventTile(
          event: p.event,
          extra: p.counted ? 'proyectado ${formatMoney(p.balance)}' : 'no se suma a la proyección',
        ),
    ]);
  }
}
