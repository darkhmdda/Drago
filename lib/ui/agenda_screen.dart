import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/money.dart';
import 'common.dart';
import 'dialogs.dart';

/// Agenda de próximos eventos: cuotas pendientes e ingresos previstos.
/// (Las vistas mensual y semanal llegan en la versión 0.3.)
class AgendaScreen extends StatelessWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final items = l.agenda(days: 90);
    // Saldo proyectado sencillo: parte del dinero real y aplica los eventos.
    var running = l.totalAvailable;
    final projections = [
      for (final it in items) running += it.isIncome ? it.amount : -it.amount,
    ];

    return PageBody(children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Próximos 90 días'),
          subtitle: Text('Saldo real hoy: ${formatMoney(l.totalAvailable)}. La columna “proyectado” es solo una estimación '
              'y nunca modifica tus saldos reales.'),
        ),
      ),
      if (items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No hay eventos próximos.'))),
      for (final (k, it) in items.indexed)
        Builder(builder: (context) {
          final projected = projections[k];
          final color = it.isIncome ? FinColors.income : (it.statusLabel == 'Vencido' ? FinColors.expense : FinColors.pending);
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(it.isIncome ? Icons.south_west : Icons.north_east, color: color, size: 20),
              ),
              title: Text(it.title),
              subtitle: Text('${fmtShortDate(it.date)} · ${it.statusLabel}\nProyectado: ${formatMoney(projected)}',
                  style: TextStyle(color: projected < 0 ? FinColors.expense : null)),
              isThreeLine: true,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(formatMoney(it.isIncome ? it.amount : -it.amount, signed: true),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (it.installmentId != null) {
                      await showPayInstallmentDialog(context, l.installment(it.installmentId!));
                    } else if (v == 'confirm') {
                      await showConfirmIncomeDialog(context, l.scheduledIncome(it.scheduledIncomeId!));
                    } else if (v == 'not') {
                      await runOp(context, (l) => l.markScheduledIncomeNotReceived(it.scheduledIncomeId!),
                          success: 'Marcado como no recibido');
                    } else if (v == 'delete') {
                      await runOp(context, (l) => l.deleteScheduledIncome(it.scheduledIncomeId!), success: 'Eliminado');
                    }
                  },
                  itemBuilder: (_) => it.installmentId != null
                      ? [const PopupMenuItem(value: 'pay', child: Text('Pagar'))]
                      : [
                          const PopupMenuItem(value: 'confirm', child: Text('Confirmar recibido')),
                          const PopupMenuItem(value: 'not', child: Text('No se recibió')),
                          const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                        ],
                ),
              ]),
            ),
          );
        }),
    ]);
  }
}
