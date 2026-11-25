import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    return PageBody(children: [
      SectionTitle('Cuentas',
          trailing: TextButton.icon(onPressed: () => _addAccount(context), icon: const Icon(Icons.add), label: const Text('Nueva'))),
      for (final a in l.accounts)
        Card(
          child: ListTile(
            leading: Icon(a.kind == AccountKind.physical ? Icons.payments_outlined : Icons.account_balance_outlined),
            title: Text(a.name + (a.archived ? ' (archivada)' : '')),
            subtitle: Text('${a.kind.label} · ${formatMoney(l.balance(a.id))}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final name = await _askText(context, 'Renombrar cuenta', a.name);
                  if (name != null && context.mounted) await runOp(context, (l) => l.renameAccount(a.id, name));
                } else {
                  await runOp(context, (l) => l.setAccountArchived(a.id, v == 'archive'));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                if (!a.archived) const PopupMenuItem(value: 'archive', child: Text('Archivar')),
                if (a.archived) const PopupMenuItem(value: 'unarchive', child: Text('Restaurar')),
              ],
            ),
          ),
        ),
      const SectionTitle('Respaldo'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Copiar respaldo'),
            subtitle: const Text('Copia toda tu información (formato JSON) al portapapeles para guardarla donde quieras.'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: AppScope.of(context).exportBackup()));
              if (context.mounted) showMessage(context, 'Respaldo copiado al portapapeles');
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('Restaurar respaldo'),
            subtitle: const Text('Pega un respaldo. Reemplaza TODA la información actual.'),
            onTap: () => _restore(context),
          ),
        ]),
      ),
      const SectionTitle('Historial de cambios'),
      Card(
        child: Column(children: [
          for (final e in l.auditLog.reversed.take(50))
            ListTile(dense: true, title: Text(e.action), subtitle: Text('${fmtDate(e.at)} · ${e.details}')),
          if (l.auditLog.isEmpty) const ListTile(title: Text('Sin cambios registrados.')),
        ]),
      ),
      const SizedBox(height: 16),
      const Center(child: Text('Drago · v0.2 · datos guardados en este dispositivo', style: TextStyle(fontSize: 12))),
    ]);
  }

  Future<String?> _askText(BuildContext context, String title, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Guardar')),
        ],
      ),
    );
  }

  Future<void> _addAccount(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final initial = TextEditingController(text: '0');
    var kind = AccountKind.digital;
    final ok = await showFormDialog<bool>(
      context,
      title: 'Nueva cuenta',
      formKey: formKey,
      onSubmit: () => true,
      builder: (c, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Mercado Pago, BBVA, cartera…', border: OutlineInputBorder()),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe un nombre' : null,
        ),
        gap,
        SegmentedButton<AccountKind>(
          segments: const [
            ButtonSegment(value: AccountKind.physical, label: Text('Físico')),
            ButtonSegment(value: AccountKind.digital, label: Text('Digital')),
          ],
          selected: {kind},
          onSelectionChanged: (s) => setState(() => kind = s.first),
        ),
        gap,
        MoneyField(controller: initial, label: 'Saldo inicial', allowZero: true),
      ]),
    );
    if (ok != true || !context.mounted) return;
    await runOp(context, (l) => l.createAccount(name.text, kind, initialBalance: parseMoney(initial.text)!),
        success: 'Cuenta creada');
  }

  Future<void> _restore(BuildContext context) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restaurar respaldo'),
        content: SizedBox(
          width: 480,
          child: TextField(controller: c, maxLines: 10, decoration: const InputDecoration(hintText: 'Pega aquí el respaldo', border: OutlineInputBorder())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Continuar')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    if (!await confirm(context, 'Reemplazar información', 'Toda tu información actual será reemplazada por el respaldo. ¿Continuar?',
            action: 'Restaurar', danger: true) ||
        !context.mounted) {
      return;
    }
    try {
      await AppScope.of(context).restoreBackup(text);
      if (context.mounted) showMessage(context, 'Respaldo restaurado');
    } on FinanceException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }
}
