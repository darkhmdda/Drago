import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';
import 'dialogs.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onOpenDebts;
  final VoidCallback onOpenAgenda;
  const HomeScreen({super.key, required this.onOpenDebts, required this.onOpenAgenda});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final now = DateTime.now();
    final month = l.monthSummary(now);
    final next = l.nextPayment;
    final nextIncome = l.nextIncome;
    final alerts = l.alerts;
    final theme = Theme.of(context);

    return PageBody(children: [
      // Total disponible
      Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total disponible', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(formatMoney(l.totalAvailable),
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Solo dinero real. No incluye ingresos previstos ni dinero por cobrar.',
                style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        final cards = [
          _KindCard(kind: AccountKind.physical, icon: Icons.payments_outlined),
          _KindCard(kind: AccountKind.digital, icon: Icons.account_balance_outlined),
        ];
        if (c.maxWidth < 560) return Column(children: cards);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final w in cards) Expanded(child: w)]);
      }),
      if (alerts.isNotEmpty) ...[
        const SectionTitle('Alertas'),
        for (final a in alerts)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.warning_amber_rounded), title: Text(a)),
          ),
      ],
      const SectionTitle('Resumen'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Tile(
          label: 'Próximo pago',
          value: next == null ? 'Sin pagos' : formatMoney(l.remainingForInstallment(next.id)),
          sub: next == null ? null : '${l.debt(next.debtId).name} · ${fmtShortDate(next.dueDate)}',
          color: FinColors.expense,
          onTap: onOpenAgenda,
        ),
        _Tile(
          label: 'Próximo ingreso',
          value: nextIncome == null ? 'Sin previstos' : formatMoney(nextIncome.amount),
          sub: nextIncome == null ? null : '${nextIncome.description} · ${fmtShortDate(nextIncome.date)} (previsto)',
          color: FinColors.income,
          onTap: onOpenAgenda,
        ),
        _Tile(
          label: 'Deudas pendientes',
          value: formatMoney(l.totalPendingDebt),
          sub: '${l.debts.where((d) => d.status == DebtStatus.active).length} activa(s)',
          color: FinColors.pending,
          onTap: onOpenDebts,
        ),
        _Tile(
          label: 'Pagos de ${DateFormat.MMMM('es_MX').format(now)}',
          value: formatMoney(l.scheduledPaymentsInMonth(now)),
          sub: 'Falta pagar ${formatMoney(l.pendingPaymentsInMonth(now))}',
          color: FinColors.pending,
          onTap: onOpenAgenda,
        ),
      ]),
      const SectionTitle('Este mes'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _row('Ingresos recibidos', month.income, FinColors.income),
            _row('Gastos', -month.expenses, FinColors.expense),
            _row('Pagos de deudas', -month.debtPayments, FinColors.expense),
            const Divider(),
            _row('Balance del mes', month.net, amountColor(month.net), bold: true),
            const SizedBox(height: 4),
            const Text('Las transferencias y ajustes no cuentan como ingreso ni gasto.', style: TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    ]);
  }

  Widget _row(String label, Cents v, Color color, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
          Text(formatMoney(v), style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

class _KindCard extends StatelessWidget {
  final AccountKind kind;
  final IconData icon;
  const _KindCard({required this.kind, required this.icon});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final accounts = l.activeAccounts.where((a) => a.kind == kind).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(kind.label, style: Theme.of(context).textTheme.titleSmall)),
            Text(formatMoney(l.totalByKind(kind)),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
          ]),
          for (final a in accounts)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 28),
              title: Text(a.name),
              subtitle: Text(formatMoney(l.balance(a.id))),
              trailing: TextButton(onPressed: () => showSetBalanceDialog(context, a), child: const Text('Corregir')),
            ),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color color;
  final VoidCallback? onTap;
  const _Tile({required this.label, required this.value, this.sub, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final width = w < 560 ? (w - 40) / 2 : 205.0;
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              if (sub != null) Text(sub!, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ),
    );
  }
}
