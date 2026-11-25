import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../data/ocr/ocr.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/statement_import.dart';
import 'common.dart';

/// Importar estado de cuenta (sección 9): se lee el texto de una captura,
/// se detectan fechas e importes, se comparan con las cuotas registradas y
/// NADA cambia hasta que el usuario elige y confirma.
class ImportScreen extends StatefulWidget {
  final String? debtId;
  const ImportScreen({super.key, this.debtId});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

const _newDebt = '__nueva__';

class _ImportScreenState extends State<ImportScreen> {
  bool _reading = false;
  String? _text;
  String? _error;
  ParsedStatement? _parsed;
  String? _debtId;
  final _selected = <int>{};
  bool _updateTotal = false;
  final _newName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _debtId = widget.debtId;
  }

  Future<void> _pick(ImageSource source) async {
    final image = await ImagePicker().pickImage(source: source, imageQuality: 95);
    if (image == null) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final text = await recognizeText(image);
      _analyze(text);
    } catch (e) {
      setState(() => _error = 'No se pudo leer la imagen: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _paste() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Pegar texto'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: c,
            maxLines: 10,
            decoration: const InputDecoration(hintText: 'Pega aquí el texto del estado de cuenta (fechas e importes)', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Analizar')),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) _analyze(text);
  }

  void _analyze(String text) {
    final l = AppScope.of(context).ledger;
    final parsed = parseStatement(text, today: l.today, extraNames: l.debts.map((d) => d.name).toList());
    final match = widget.debtId ?? matchDebt(l, parsed)?.id;
    setState(() {
      _text = text;
      _parsed = parsed;
      _debtId = match ?? (l.debts.any((d) => d.status == DebtStatus.active) ? null : _newDebt);
      _newName.text = parsed.institution ?? '';
      _updateTotal = false;
      _resetSelection();
    });
  }

  List<ProposedChange> _changes() {
    final l = AppScope.of(context).ledger;
    final p = _parsed;
    if (p == null || _debtId == null || _debtId == _newDebt) return const [];
    final d = l.debts.where((x) => x.id == _debtId).firstOrNull;
    return d == null ? const [] : compareWithDebt(l, d, p);
  }

  void _resetSelection() {
    _selected.clear();
    final c = _changes();
    for (var i = 0; i < c.length; i++) {
      if (c[i].kind == ChangeKind.update || c[i].kind == ChangeKind.newInstallment) _selected.add(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final p = _parsed;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar captura')),
      body: PageBody(children: [
        const Text('Sube una captura o foto de tu app de pagos (DiDi, Coppel, Mercado Pago…). Drago lee las fechas e importes '
            'y te muestra qué cambiaría. La imagen se procesa en este dispositivo y no se guarda.'),
        gap,
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _reading || !ocrAvailable ? null : () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.image_outlined),
            label: const Text('Elegir captura'),
          ),
          if (!kIsWeb)
            OutlinedButton.icon(
              onPressed: _reading || !ocrAvailable ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Tomar foto'),
            ),
          OutlinedButton.icon(onPressed: _reading ? null : _paste, icon: const Icon(Icons.content_paste), label: const Text('Pegar texto')),
        ]),
        if (!ocrAvailable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('El lector de imágenes no está disponible aquí; puedes pegar el texto.', style: TextStyle(fontSize: 13)),
          ),
        if (_reading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Leyendo la imagen…')]),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (p != null && !_reading) ...[
          const SectionTitle('Detectado'),
          if (p.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.search_off),
                title: Text('No encontré fechas con importes'),
                subtitle: Text('Prueba con una captura más nítida de la sección de pagos o cuotas, o pega el texto.'),
              ),
            )
          else ...[
            Card(
              child: Column(children: [
                ListTile(dense: true, title: const Text('Institución'), trailing: Text(p.institution ?? 'No identificada')),
                ListTile(dense: true, title: const Text('Pagos encontrados'), trailing: Text('${p.payments.length}')),
                if (p.totalPending != null)
                  ListTile(dense: true, title: const Text('Saldo pendiente'), trailing: Text(formatMoney(p.totalPending!))),
              ]),
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _debtId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Comparar con la deuda', border: OutlineInputBorder()),
              items: [
                for (final d in l.debts.where((d) => d.status == DebtStatus.active)) DropdownMenuItem(value: d.id, child: Text(d.name)),
                const DropdownMenuItem(value: _newDebt, child: Text('Crear una deuda nueva con estos pagos')),
              ],
              onChanged: (v) => setState(() {
                _debtId = v;
                _updateTotal = false;
                _resetSelection();
              }),
            ),
            if (_debtId == _newDebt) ..._newDebtSection(p) else if (_debtId != null) ..._compareSection(l, p),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Ver el texto leído'),
            children: [SelectableText(_text ?? '', style: const TextStyle(fontSize: 12))],
          ),
        ],
      ]),
    );
  }

  List<Widget> _compareSection(Ledger l, ParsedStatement p) {
    final changes = _changes();
    final debt = l.debt(_debtId!);
    final summary = l.summaryOf(debt.id);
    final totalDiffers = p.totalPending != null && p.totalPending != summary.remaining;
    final fin = FinColors.of(context);
    final count = _selected.length + (_updateTotal ? 1 : 0);
    return [
      const SectionTitle('Cambios propuestos'),
      Card(
        child: Column(children: [
          const ListTile(
            dense: true,
            title: Row(children: [
              Expanded(flex: 3, child: Text('Concepto', style: TextStyle(fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('Antes', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('Detectado', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
          for (final (i, c) in changes.indexed)
            CheckboxListTile(
              dense: true,
              value: _selected.contains(i),
              onChanged: c.kind == ChangeKind.update || c.kind == ChangeKind.newInstallment
                  ? (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i))
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(children: [
                Expanded(flex: 3, child: Text('${debt.name.split(' ').first} ${fmtShortDate(c.detected.date)}')),
                Expanded(flex: 2, child: Text(c.before == null ? '—' : formatMoney(c.before!), textAlign: TextAlign.right)),
                Expanded(
                  flex: 2,
                  child: Text(formatMoney(c.detected.amount),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.kind == ChangeKind.update ? fin.pending : null)),
                ),
              ]),
              subtitle: Text(switch (c.kind) {
                ChangeKind.update => c.installment!.dueDate != c.detected.date
                    ? 'Actualizar (fecha ${fmtShortDate(c.installment!.dueDate)} → ${fmtShortDate(c.detected.date)})'
                    : 'Actualizar importe',
                ChangeKind.newInstallment => 'Cuota nueva',
                ChangeKind.unchanged => 'Sin cambios',
                ChangeKind.alreadyPaid => 'Ya pagada: no se toca',
              }),
            ),
          if (totalDiffers)
            CheckboxListTile(
              dense: true,
              value: _updateTotal,
              onChanged: (v) => setState(() => _updateTotal = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(children: [
                const Expanded(flex: 3, child: Text('Saldo pendiente')),
                Expanded(flex: 2, child: Text(formatMoney(summary.remaining), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text(formatMoney(p.totalPending!), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              subtitle: Text('Ajustar el monto total de la deuda a ${formatMoney(summary.paid + p.totalPending!)}'),
            ),
        ]),
      ),
      gap,
      FilledButton.icon(
        onPressed: count == 0 ? null : () => _apply(changes, totalDiffers && _updateTotal ? summary.paid + p.totalPending! : null),
        icon: const Icon(Icons.check),
        label: Text(count == 0 ? 'Nada seleccionado' : 'Aplicar $count cambio(s)'),
      ),
      const SizedBox(height: 4),
      const Text('No se borra ninguna cuota y nada cambia hasta que confirmes.', style: TextStyle(fontSize: 12)),
    ];
  }

  List<Widget> _newDebtSection(ParsedStatement p) {
    final sum = p.payments.fold<int>(0, (s, x) => s + x.amount);
    final total = p.totalPending ?? sum;
    return [
      gap,
      TextField(controller: _newName, decoration: const InputDecoration(labelText: 'Nombre de la deuda', border: OutlineInputBorder())),
      gap,
      Card(
        child: Column(children: [
          for (final x in p.payments)
            ListTile(dense: true, title: Text(fmtDate(x.date)), trailing: Text(formatMoney(x.amount))),
          ListTile(dense: true, title: const Text('Monto total'), trailing: Text(formatMoney(total), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
      gap,
      FilledButton.icon(
        onPressed: p.payments.isEmpty
            ? null
            : () async {
                final name = _newName.text.trim().isEmpty ? (p.institution ?? 'Deuda importada') : _newName.text.trim();
                if (!await confirm(context, 'Crear deuda', '«$name» con ${p.payments.length} cuota(s) y monto total ${formatMoney(total)}.') ||
                    !mounted) {
                  return;
                }
                final ok = await runOp(
                  context,
                  (l) => l.addDebt(
                    name: name,
                    total: total,
                    startDate: l.today,
                    description: 'Importada desde captura',
                    installments: [for (final x in p.payments) (amount: x.amount, dueDate: x.date)],
                  ),
                  success: 'Deuda creada',
                );
                if (ok && mounted) Navigator.pop(context);
              },
        icon: const Icon(Icons.add),
        label: const Text('Crear deuda'),
      ),
    ];
  }

  Future<void> _apply(List<ProposedChange> changes, Cents? newTotal) async {
    final chosen = [for (final i in _selected) changes[i]];
    final lines = [
      for (final c in chosen)
        c.kind == ChangeKind.newInstallment
            ? 'Nueva cuota: ${fmtShortDate(c.detected.date)} · ${formatMoney(c.detected.amount)}'
            : '${fmtShortDate(c.detected.date)}: ${formatMoney(c.before!)} → ${formatMoney(c.detected.amount)}',
      if (newTotal != null) 'Monto total: ${formatMoney(newTotal)}',
    ];
    if (!await confirm(context, 'Confirmar cambios', lines.join('\n'), action: 'Aplicar') || !mounted) return;
    final debtId = _debtId!;
    final ok = await runOp(context, (l) {
      applyChanges(l, l.debt(debtId), chosen);
      if (newTotal != null) l.updateDebt(debtId, total: newTotal);
    }, success: 'Cambios aplicados');
    if (ok && mounted) Navigator.pop(context);
  }
}
