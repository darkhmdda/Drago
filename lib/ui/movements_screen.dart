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
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
        title: Text(t.description),
        subtitle: Text([fmtDate(t.date), t.type.label, accountText, ?t.category].join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(t.type == TxType.transfer && focusAccount == null ? formatMoney(shown) : formatMoney(shown, signed: true),
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () async {
              final extra = t.type == TxType.debtPayment
                  ? '\nLa cuota volverá a quedar pendiente.'
                  : (t.scheduledItemId != null ? '\nEl ingreso volverá a quedar como previsto.' : '');
              if (await confirm(context, 'Eliminar movimiento',
                      '${t.description} · ${formatMoney(t.amount)}\nEl saldo se recalculará.$extra',
                      action: 'Eliminar', danger: true) &&
                  context.mounted) {
                await runOp(context, (l) => l.deleteTransaction(t.id), success: 'Movimiento eliminado');
              }
            },
          ),
        ]),
      ),
    );
  }
}
