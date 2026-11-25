import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/scenarios.dart';
import 'common.dart';
import 'projection_chart.dart';

/// Historial de saldos: cómo ha cambiado tu dinero real y cuánto tenías en
/// cualquier fecha (solo movimientos confirmados).
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  int _days = 30;
  bool _split = false;
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final fin = FinColors.of(context);
    final today = l.today;
    final first = l.transactions.isEmpty
        ? today
        : l.transactions.map((t) => t.date).reduce((a, b) => a.isBefore(b) ? a : b);
    // Empieza en el primer movimiento (sin meses vacíos en cero).
    final wanted = _days == 0 ? first : today.subtract(Duration(days: _days));
    final from = wanted.isBefore(first) ? first : wanted;
    final hist = balanceHistory(l, from.isAfter(today) ? today : from, today);
    final date = _date ?? today;
    final (dPhys, dDig) = (l.totalByKind(AccountKind.physical, asOf: date), l.totalByKind(AccountKind.digital, asOf: date));
    final dayTx = l.transactionsSorted.where((t) => t.date == date).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 30, label: Text('30 días')),
          ButtonSegment(value: 90, label: Text('90 días')),
          ButtonSegment(value: 365, label: Text('1 año')),
          ButtonSegment(value: 0, label: Text('Todo')),
        ],
        selected: {_days},
        onSelectionChanged: (v) => setState(() => _days = v.first),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Saldo real por día', style: Theme.of(context).textTheme.titleSmall)),
              FilterChip(label: const Text('Físico vs digital'), selected: _split, onSelected: (v) => setState(() => _split = v)),
            ]),
            const SizedBox(height: 8),
            if (hist.length < 2)
              const Padding(padding: EdgeInsets.all(24), child: Text('Aún no hay suficiente historial.'))
            else
              ProjectionChart(series: [
                if (!_split) ChartSeries('Total', fin.chartBase, [for (final (d, p, g) in hist) (d, p + g)]),
                if (_split) ChartSeries('Físico', fin.chartBase, [for (final (d, p, _) in hist) (d, p)]),
                if (_split) ChartSeries('Digital', fin.chartScenario, [for (final (d, _, g) in hist) (d, g)]),
              ]),
          ]),
        ),
      ),
      SectionTitle('¿Cuánto tenía en una fecha?'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DateField(label: 'Fecha', value: date, onChanged: (d) => setState(() => _date = dayOf(d))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Figure('Físico', dPhys)),
              Expanded(child: _Figure('Digital', dDig)),
              Expanded(child: _Figure('Total', dPhys + dDig, bold: true)),
            ]),
            const SizedBox(height: 4),
            Text('Saldo al cierre del día, con los movimientos confirmados hasta esa fecha.', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      SectionTitle(dayTx.isEmpty ? 'Sin movimientos ese día' : 'Movimientos de ese día'),
      for (final t in dayTx)
        Card(
          child: ListTile(
            dense: true,
            title: Text(t.description),
            subtitle: Text('${t.type.label} · ${l.account(t.accountId).name}${t.toAccountId == null ? '' : ' → ${l.account(t.toAccountId!).name}'}'),
            trailing: Text(
              t.type == TxType.transfer ? formatMoney(t.amount) : formatMoney(t.effectOn(t.accountId), signed: true),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.type == TxType.transfer ? fin.neutral : amountColor(context, t.effectOn(t.accountId)),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final Cents value;
  final bool bold;
  const _Figure(this.label, this.value, {this.bold = false});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(formatMoney(value), style: TextStyle(fontSize: bold ? 18 : 16, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]);
}
