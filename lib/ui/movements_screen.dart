import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';

class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});
  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  TxType? _filter;
  String? _account;

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    var txs = l.transactionsSorted;
    if (_filter != null) txs = txs.where((t) => t.type == _filter).toList();
    if (_account != null) txs = txs.where((t) => t.accountId == _account || t.toAccountId == _account).toList();

    return PageBody(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: const Text('Todos'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
          ),
          for (final t in TxType.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(t.label), selected: _filter == t, onSelected: (_) => setState(() => _filter = t)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      DropdownButton<String?>(
        value: _account,
        hint: const Text('Todas las cuentas'),
        isExpanded: true,
        items: [
          const DropdownMenuItem(value: null, child: Text('Todas las cuentas')),
          for (final a in l.accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
        ],
        onChanged: (v) => setState(() => _account = v),
      ),
      if (txs.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Sin movimientos.'))),
      for (final t in txs) _TxTile(t: t, focusAccount: _account),
    ]);
  }
}

class _TxTile extends StatelessWidget {
  final Transaction t;
  final String? focusAccount;
  const _TxTile({required this.t, this.focusAccount});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final acc = l.account(t.accountId).name;
    final String accountText;
    final Cents shown;
    if (t.type == TxType.transfer) {
      accountText = '$acc → ${l.account(t.toAccountId!).name}';
      shown = focusAccount == null ? t.amount : t.effectOn(focusAccount!);
    } else {
      accountText = acc;
      shown = t.effectOn(t.accountId);
    }
    final icon = switch (t.type) {
      TxType.income => Icons.arrow_downward,
      TxType.expense => Icons.arrow_upward,
      TxType.debtPayment => Icons.receipt_long,
      TxType.transfer => Icons.swap_horiz,
      TxType.adjustment => Icons.tune,
    };
    final color = t.type == TxType.transfer && focusAccount == null ? FinColors.of(context).neutral : amountColor(context, shown);
    final amountText = t.type == TxType.transfer && focusAccount == null ? formatMoney(shown) : formatMoney(shown, signed: true);
    return Card(
      child: ListTile(
        onTap: () => _showDetails(context, accountText, amountText, color, icon),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
        title: Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        // El tipo ya lo indica el icono: aquí solo fecha, cuenta y categoría.
        subtitle: Text([fmtShortDate(t.date), accountText, ?t.category].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(amountText, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, String accountText, String amountText, Color color, IconData icon) async {
    final l = AppScope.of(context).ledger;
    final delete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
            title: Text(t.description),
            subtitle: Text(t.type.label),
            trailing: Text(amountText, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const Divider(),
          _row(c, 'Fecha', fmtDate(t.date)),
          _row(c, t.type == TxType.transfer ? 'Cuentas' : 'Cuenta', accountText),
          if (t.category != null) _row(c, 'Categoría', t.category!),
          if (t.debtId != null && l.debts.any((d) => d.id == t.debtId)) _row(c, 'Deuda', l.debt(t.debtId!).name),
          _row(c, 'Registrado', '${fmtDate(t.createdAt.toLocal())}, ${TimeOfDay.fromDateTime(t.createdAt.toLocal()).format(c)}'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar movimiento'),
            ),
          ),
        ]),
      ),
    );
    if (delete != true || !context.mounted) return;
    final extra = t.type == TxType.debtPayment
        ? '\nLa cuota volverá a quedar pendiente.'
        : (t.scheduledItemId != null ? '\nVolverá a quedar como previsto en el calendario.' : '');
    if (await confirm(context, 'Eliminar movimiento', '${t.description} · ${formatMoney(t.amount)}\nEl saldo se recalculará.$extra',
            action: 'Eliminar', danger: true) &&
        context.mounted) {
      await runOp(context, (l) => l.deleteTransaction(t.id), success: 'Movimiento eliminado');
    }
  }

  Widget _row(BuildContext c, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(k, style: Theme.of(c).textTheme.bodySmall)),
          Expanded(child: Text(v)),
        ]),
      );
}
