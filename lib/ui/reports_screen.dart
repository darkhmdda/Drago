import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../data/exporter.dart';
import '../data/pdf_export.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/report.dart';
import 'common.dart';
import 'history_view.dart';
import 'projections_view.dart';

/// Reportes: resumen mensual y exportación a Excel / CSV.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _MonthData {
  int income = 0, expenses = 0, debtPayments = 0;
  final byCategory = <String, int>{};
  final incomeByCategory = <String, int>{};
  final byDebt = <String, int>{};
  int get net => income - expenses - debtPayments;
}

_MonthData _monthData(Ledger l, DateTime m) {
  final d = _MonthData();
  for (final t in l.transactions) {
    if (t.date.year != m.year || t.date.month != m.month) continue;
    switch (t.type) {
      case TxType.income:
        d.income += t.amount;
        final c = t.category ?? 'Sin categoría';
        d.incomeByCategory[c] = (d.incomeByCategory[c] ?? 0) + t.amount;
      case TxType.expense:
        d.expenses += t.amount;
        final c = t.category ?? 'Sin categoría';
        d.byCategory[c] = (d.byCategory[c] ?? 0) + t.amount;
      case TxType.debtPayment:
        d.debtPayments += t.amount;
        final name = l.debts.where((x) => x.id == t.debtId).map((x) => x.name).firstOrNull ?? 'Deuda';
        d.byDebt[name] = (d.byDebt[name] ?? 0) + t.amount;
      default:
        break;
    }
  }
  return d;
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;
  int _tab = 0;

  Widget get _tabs => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Mensual')),
            ButtonSegment(value: 1, label: Text('Proyección')),
            ButtonSegment(value: 2, label: Text('Historial')),
          ],
          selected: {_tab},
          onSelectionChanged: (v) => setState(() => _tab = v.first),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final fin = FinColors.of(context);
    final cur = _monthData(l, _month);
    final prev = _monthData(l, DateTime(_month.year, _month.month - 1));
    final label = toBeginningOfSentenceCase(DateFormat('MMMM y', 'es_MX').format(_month));

    if (_tab == 1) return PageBody(children: [_tabs, const ProjectionsView()]);
    if (_tab == 2) return PageBody(children: [_tabs, const HistoryView()]);
    return PageBody(children: [
      _tabs,
      Row(children: [
        IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
      ]),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _line(context, 'Ingresos recibidos', cur.income, prev.income, fin.income, higherIsGood: true),
            _line(context, 'Gastos', cur.expenses, prev.expenses, fin.expense, higherIsGood: false),
            _line(context, 'Pagos de deudas', cur.debtPayments, prev.debtPayments, fin.pending, higherIsGood: false),
            const Divider(),
            _line(context, 'Balance del mes', cur.net, prev.net, amountColor(context, cur.net), higherIsGood: true, bold: true),
            const SizedBox(height: 4),
            Text('Comparado con el mes anterior. Solo movimientos reales; transferencias y ajustes no cuentan.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      if (cur.byCategory.isNotEmpty) ...[
        const SectionTitle('Gastos por categoría'),
        _Breakdown(values: cur.byCategory, color: fin.expense),
      ],
      if (cur.byDebt.isNotEmpty) ...[
        const SectionTitle('Pagos por deuda'),
        _Breakdown(values: cur.byDebt, color: fin.pending),
      ],
      if (cur.incomeByCategory.isNotEmpty) ...[
        const SectionTitle('Ingresos por categoría'),
        _Breakdown(values: cur.incomeByCategory, color: fin.income),
      ],
      if (cur.income == 0 && cur.expenses == 0 && cur.debtPayments == 0)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Sin movimientos reales en este mes.'))),
      const SectionTitle('Exportar'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.table_view),
            title: const Text('Excel completo'),
            subtitle: const Text('Resumen, movimientos, deudas, cuotas, calendario y proyección (.xlsx)'),
            trailing: const Icon(Icons.download),
            enabled: !_busy,
            onTap: () => _export(ReportScope.full, csv: false),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Reporte en PDF'),
            subtitle: const Text('El mismo contenido, listo para imprimir o compartir'),
            trailing: const Icon(Icons.download),
            enabled: !_busy,
            onTap: () => _export(ReportScope.full, csv: false, pdf: true),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.credit_card),
            title: const Text('Solo deudas'),
            subtitle: const Text('Deudas y todas sus cuotas (.xlsx)'),
            trailing: const Icon(Icons.download),
            enabled: !_busy,
            onTap: () => _export(ReportScope.debtsOnly, csv: false, askPeriod: false),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Movimientos (CSV)'),
            subtitle: const Text('Para abrir en cualquier hoja de cálculo'),
            trailing: const Icon(Icons.download),
            enabled: !_busy,
            onTap: () => _export(ReportScope.movementsOnly, csv: true),
          ),
        ]),
      ),
    ]);
  }

  Widget _line(BuildContext context, String label, int value, int previous, Color color,
      {required bool higherIsGood, bool bold = false}) {
    final diff = value - previous;
    String? change;
    Color? changeColor;
    if (previous != 0 || value != 0) {
      if (diff == 0) {
        change = 'igual';
      } else {
        change = previous == 0 ? 'nuevo' : '${diff > 0 ? '+' : ''}${(diff * 100 / previous.abs()).round()}%';
        final good = higherIsGood ? diff > 0 : diff < 0;
        changeColor = good ? FinColors.of(context).income : FinColors.of(context).expense;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
        if (change != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(change, style: TextStyle(fontSize: 12, color: changeColor ?? FinColors.of(context).neutral)),
          ),
        Text(formatMoney(value), style: TextStyle(color: value == 0 ? FinColors.of(context).neutral : color, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Future<Period?> _askPeriod() async {
    final now = DateTime.now();
    final fmt = DateFormat('MMMM y', 'es_MX');
    final options = <(String, Period)>[
      ('Mes mostrado (${fmt.format(_month)})', Period.month(_month, fmt.format(_month))),
      ('Este mes y el anterior', Period(DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month + 1, 0), 'Últimos 2 meses')),
      ('Este año (${now.year})', Period(DateTime(now.year, 1, 1), DateTime(now.year, 12, 31), 'Año ${now.year}')),
      ('Todo el historial', Period(DateTime(2000), DateTime(now.year + 5, 12, 31), 'Todo el historial')),
    ];
    return showModalBottomSheet<Period>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('¿Qué periodo exportar?', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final (label, p) in options) ListTile(title: Text(label), onTap: () => Navigator.pop(c, p)),
          ListTile(
            title: const Text('Personalizado…'),
            trailing: const Icon(Icons.date_range),
            onTap: () async {
              final r = await showDateRangePicker(
                context: c,
                firstDate: DateTime(2000),
                lastDate: DateTime(now.year + 5),
                initialDateRange: DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
                locale: const Locale('es', 'MX'),
              );
              if (r != null && c.mounted) {
                Navigator.pop(c, Period(dayOf(r.start), dayOf(r.end), '${fmtDate(r.start)} – ${fmtDate(r.end)}'));
              }
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _export(ReportScope scope, {required bool csv, bool pdf = false, bool askPeriod = true}) async {
    final l = AppScope.of(context).ledger;
    final now = DateTime.now();
    final period = askPeriod ? await _askPeriod() : Period(DateTime(2000), DateTime(now.year + 5, 12, 31), 'Todas las deudas');
    if (period == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final stamp = DateFormat('yyyy-MM-dd').format(now);
      final tables = buildReport(l, period, scope: scope);
      if (pdf) {
        final bytes = await buildPdf(tables, title: 'Reporte financiero · ${period.label}', subtitle: 'Generado el ${fmtDate(now)}');
        await saveFile(bytes, 'drago_reporte_$stamp.pdf', pdfMime);
      } else if (csv) {
        await saveFile(buildCsv(tables.first), 'drago_movimientos_$stamp.csv', csvMime);
      } else {
        final name = scope == ReportScope.debtsOnly ? 'drago_deudas_$stamp.xlsx' : 'drago_reporte_$stamp.xlsx';
        await saveFile(buildXlsx(tables), name, xlsxMime);
      }
      if (mounted) showMessage(context, 'Archivo generado');
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo exportar: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Breakdown extends StatelessWidget {
  final Map<String, int> values;
  final Color color;
  const _Breakdown({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(e.key)),
                  Text('${(e.value * 100 / total).round()}%  ', style: Theme.of(context).textTheme.bodySmall),
                  Text(formatMoney(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : e.value / total,
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
