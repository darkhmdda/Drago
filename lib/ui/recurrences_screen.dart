import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';
import 'scheduled_dialogs.dart';

/// Lista de reglas recurrentes (ingresos y gastos).
class RecurrencesScreen extends StatelessWidget {
  const RecurrencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final incomes = l.recurrences.where((r) => r.isIncome).toList();
    final expenses = l.recurrences.where((r) => !r.isIncome).toList();
    final monthlyIncome = incomes.where((r) => r.active).fold<int>(0, (s, r) => s + _monthlyEstimate(r));

    return Scaffold(
      appBar: AppBar(title: const Text('Recurrentes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showScheduledForm(context, isIncome: true),
        icon: const Icon(Icons.add),
        label: const Text('Nueva regla'),
      ),
      body: PageBody(children: [
        const Text('Cada regla genera fechas previstas en el calendario. Ninguna cambia tu saldo real hasta que '
            'confirmes cada fecha por separado.'),
        if (incomes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Ingreso recurrente estimado: ${formatMoney(monthlyIncome)} al mes',
                style: TextStyle(fontWeight: FontWeight.w600, color: FinColors.of(context).income)),
          ),
        const SectionTitle('Ingresos'),
        if (incomes.isEmpty) const Text('Sin ingresos recurrentes. Ejemplo: \$400 cada sábado.'),
        for (final r in incomes) _RecurrenceTile(r),
        const SectionTitle('Gastos y pagos'),
        if (expenses.isEmpty) const Text('Sin gastos recurrentes.'),
        for (final r in expenses) _RecurrenceTile(r),
      ]),
    );
  }

  /// Estimación mensual aproximada (solo informativa).
  static int _monthlyEstimate(Recurrence r) => switch (r.frequency) {
        Frequency.daily => r.amount * 30,
        Frequency.weekly => r.amount * 52 ~/ 12,
        Frequency.biweekly => r.amount * 2,
        Frequency.monthly => r.amount,
        Frequency.custom => r.amount * 30 ~/ (r.intervalDays < 1 ? 1 : r.intervalDays),
      };
}

class _RecurrenceTile extends StatelessWidget {
  final Recurrence r;
  const _RecurrenceTile(this.r);

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final color = !r.active ? FinColors.of(context).neutral : (r.isIncome ? FinColors.of(context).income : FinColors.of(context).pending);
    final next = r.occurrences(l.today, l.today.add(const Duration(days: 400)));
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(Icons.repeat, color: color)),
        title: Text(r.description + (r.active ? '' : ' (pausada)')),
        subtitle: Text([
          '${r.frequency.label}: ${r.scheduleLabel.toLowerCase()}',
          l.account(r.accountId).name,
          if (r.active && next.isNotEmpty) 'próxima: ${fmtShortDate(next.first)}',
          if (r.endDate != null) 'hasta ${fmtDate(r.endDate!)}',
        ].join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(formatMoney(r.isIncome ? r.amount : -r.amount, signed: true),
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await showScheduledForm(context, editing: r);
                case 'pause':
                  await runOp(context, (l) => l.setRecurrenceActive(r.id, !r.active),
                      success: r.active ? 'Regla pausada' : 'Regla reanudada');
                case 'delete':
                  if (await confirm(context, 'Eliminar regla',
                          'Se quitarán del calendario las fechas futuras de «${r.description}». Los ingresos o pagos ya confirmados se conservan.',
                          action: 'Eliminar', danger: true) &&
                      context.mounted) {
                    await runOp(context, (l) => l.deleteRecurrence(r.id), success: 'Regla eliminada');
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'pause', child: Text(r.active ? 'Pausar' : 'Reanudar')),
              const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
        ]),
        onTap: () => showScheduledForm(context, editing: r),
      ),
    );
  }
}
