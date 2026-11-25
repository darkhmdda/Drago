import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'themes.dart';

final _dateFmt = DateFormat('d MMM y', 'es_MX');
final _shortDateFmt = DateFormat('EEE d MMM', 'es_MX');
String fmtDate(DateTime d) => _dateFmt.format(d);
String fmtShortDate(DateTime d) => _shortDateFmt.format(d);

/// Colores con significado financiero del tema activo.
class FinColors {
  static FinPalette of(BuildContext context) => Theme.of(context).extension<FinPalette>()!;
}

Color amountColor(BuildContext context, Cents c) {
  final f = FinColors.of(context);
  return c > 0 ? f.income : (c < 0 ? f.expense : f.neutral);
}

void showMessage(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}

/// Ejecuta una operación financiera mostrando el error si falla.
/// Devuelve true si se aplicó.
Future<bool> runOp(BuildContext context, void Function(Ledger l) op, {String? success}) async {
  final state = AppScope.of(context);
  try {
    await state.run(op);
    if (context.mounted && success != null) showMessage(context, success);
    return true;
  } on FinanceException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
    return false;
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String action = 'Confirmar', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Campo de importe. Valida y convierte a centavos sin usar double.
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool allowZero;
  final bool autofocus;
  const MoneyField({super.key, required this.controller, this.label = 'Importe', this.allowZero = false, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      decoration: InputDecoration(labelText: label, prefixText: r'$ ', border: const OutlineInputBorder()),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      validator: (v) {
        final c = parseMoney(v ?? '');
        if (c == null) return 'Escribe una cantidad válida (ej. 750.00)';
        if (c < 0 || (!allowZero && c == 0)) return 'Debe ser mayor que cero';
        return null;
      },
    );
  }
}

String centsToInput(Cents c) => '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';

class DateField extends StatelessWidget {
  final DateTime value;
  final String label;
  final ValueChanged<DateTime> onChanged;
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Fecha'});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          locale: const Locale('es', 'MX'),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.event)),
        child: Text(fmtDate(value)),
      ),
    );
  }
}

class AccountDropdown extends StatelessWidget {
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final String? excludeId;
  const AccountDropdown({super.key, required this.value, required this.onChanged, this.label = 'Cuenta', this.excludeId});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    final accounts = l.activeAccounts.where((a) => a.id != excludeId).toList();
    return DropdownButtonFormField<String>(
      initialValue: accounts.any((a) => a.id == value) ? value : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final a in accounts)
          DropdownMenuItem(
            value: a.id,
            // El icono indica si es dinero físico o digital; así el texto cabe.
            child: Row(children: [
              Icon(a.kind == AccountKind.physical ? Icons.payments_outlined : Icons.account_balance_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(formatMoney(l.balance(a.id)), style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
      ],
      onChanged: onChanged,
      validator: (v) => v == null ? 'Elige una cuenta' : null,
      isExpanded: true,
    );
  }
}

/// Encabezado de sección.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          ?trailing,
        ]),
      );
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

Color installmentColor(BuildContext context, InstallmentStatus s) => switch (s) {
      InstallmentStatus.paid => FinColors.of(context).income,
      InstallmentStatus.overdue => FinColors.of(context).expense,
      InstallmentStatus.partial => FinColors.of(context).pending,
      InstallmentStatus.pending => FinColors.of(context).pending,
      InstallmentStatus.cancelled => FinColors.of(context).neutral,
    };

/// Contenedor con ancho máximo para pantallas grandes (web).
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: children),
        ),
      );
}

/// Diálogo con formulario estándar.
/// Formulario estándar. En pantallas angostas (teléfono) se abre a pantalla
/// completa con desplazamiento y el botón de guardar siempre visible, para que
/// el teclado no tape campos; en pantallas anchas, como diálogo.
///
/// [title] puede ser un texto o una función (para títulos que cambian según
/// lo que se elige dentro del formulario).
Future<T?> showFormDialog<T>(BuildContext context,
    {required Object title,
    required Widget Function(BuildContext, StateSetter) builder,
    required T? Function() onSubmit,
    required GlobalKey<FormState> formKey,
    String action = 'Guardar'}) {
  String titleText() => title is String Function() ? title() : '$title';
  void submit(BuildContext c) {
    if (formKey.currentState!.validate()) Navigator.pop(c, onSubmit());
  }

  if (MediaQuery.sizeOf(context).width < 600) {
    return Navigator.of(context).push<T>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => Scaffold(
          appBar: AppBar(
            title: Text(titleText()),
            leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancelar', onPressed: () => Navigator.pop(c)),
          ),
          body: Form(
            key: formKey,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [builder(c, setState)]),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.viewInsetsOf(c).bottom),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => submit(c),
                child: Text(action),
              ),
            ),
          ),
        ),
      ),
    ));
  }
  return showDialog<T>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(titleText()),
        content: SizedBox(
          width: 420,
          child: Form(key: formKey, child: SingleChildScrollView(child: builder(c, setState))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => submit(c), child: Text(action)),
        ],
      ),
    ),
  );
}

const gap = SizedBox(height: 12);
