import 'package:material_ui/material_ui.dart';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'common.dart';
import '../data/exporter.dart';
import '../data/sync_scope.dart';
import '../data/sync_service.dart';
import 'sync_widgets.dart';
import 'themes.dart';
import 'notifications_screen.dart';
import 'lock_screen.dart';
import '../data/app_lock.dart';
import '../domain/reminders.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).ledger;
    return PageBody(children: [
      const SectionTitle('Cuenta y sincronización'),
      const AccountSection(),
      SectionTitle('Cuentas de dinero',
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
      const SectionTitle('Seguridad'),
      const _SecuritySection(),
      const SectionTitle('Recordatorios'),
      const _ReminderSettings(),
      const SectionTitle('Apariencia'),
      const _ThemePicker(),
      const SectionTitle('Respaldo'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Descargar respaldo'),
            subtitle: const Text('Archivo con toda tu información (.json). Guárdalo en un lugar seguro.'),
            onTap: () async {
              final json = AppScope.of(context).exportBackup();
              final stamp = DateTime.now().toIso8601String().substring(0, 10);
              await saveFile(Uint8List.fromList(utf8.encode(json)), 'drago_respaldo_$stamp.json', 'application/json');
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Restaurar desde archivo'),
            subtitle: const Text('Elige un archivo de respaldo. Reemplaza TODA la información actual.'),
            onTap: () => _restoreFromFile(context),
          ),
          const Divider(height: 1),
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
      const SectionTitle('Zona de peligro'),
      Card(
        child: ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
          title: Text('Borrar todos mis datos', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          subtitle: const Text('Deja la cuenta limpia: movimientos, deudas, previstos, simulaciones e historial. '
              'Si tienes sesión iniciada, también se borra de la nube y de tus otros dispositivos.'),
          onTap: () => _wipe(context),
        ),
      ),
      const SizedBox(height: 16),
      const Center(child: Text('Drago · v1.0 · los datos se guardan primero en este dispositivo', style: TextStyle(fontSize: 12))),
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

  Future<void> _wipe(BuildContext context) async {
    final sync = SyncScope.of(context).sync;
    final signedIn = sync != null && sync.status != SyncStatus.signedOut;
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: const Text('Borrar todos mis datos'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(signedIn
                  ? 'Se borrará TODO en este dispositivo, en la nube y en tus otros dispositivos. Tu cuenta, tema y '
                      'recordatorios se conservan. Esta acción no se puede deshacer.'
                  : 'Se borrará TODO en este dispositivo. Esta acción no se puede deshacer.'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final json = AppScope.of(context).exportBackup();
                  final stamp = DateTime.now().toIso8601String().substring(0, 10);
                  await saveFile(Uint8List.fromList(utf8.encode(json)), 'drago_respaldo_$stamp.json', 'application/json');
                },
                icon: const Icon(Icons.save_alt),
                label: const Text('Descargar un respaldo antes'),
              ),
              const SizedBox(height: 8),
              const Text('Para confirmar escribe BORRAR:'),
              const SizedBox(height: 6),
              TextField(controller: c, autofocus: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error),
              onPressed: c.text.trim().toUpperCase() == 'BORRAR' ? () => Navigator.pop(d, true) : null,
              child: const Text('Borrar todo'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final fresh = Ledger.withDefaults();
      if (sync != null) {
        await sync.wipeEverything(fresh);
      } else {
        await AppScope.of(context).replaceFromSync(fresh);
      }
      if (context.mounted) showMessage(context, 'Listo: tu cuenta está limpia.');
    } on SyncFailure catch (e) {
      if (context.mounted) showMessage(context, '${e.message} No se borró nada.', error: true);
    } catch (e) {
      if (context.mounted) showMessage(context, 'No se pudo borrar: $e. No se borró nada.', error: true);
    }
  }

  Future<void> _restoreFromFile(BuildContext context) async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    if (files.isEmpty || !context.mounted) return;
    final String text;
    try {
      text = utf8.decode(await files.first.readAsBytes());
    } catch (_) {
      if (context.mounted) showMessage(context, 'No se pudo leer el archivo.', error: true);
      return;
    }
    if (!context.mounted) return;
    if (!await confirm(context, 'Reemplazar información', 'Toda tu información actual será reemplazada por el respaldo «${files.first.name}». ¿Continuar?',
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

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 600 ? 2 : 1;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in AppTheme.values)
          SizedBox(width: w, child: _ThemeCard(theme: t, selected: controller.theme == t, onTap: () => controller.set(t))),
      ]);
    });
  }
}

class _ThemeCard extends StatelessWidget {
  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeCard({required this.theme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Vista previa con los colores reales de ese tema.
    final preview = theme.data;
    final fin = preview.extension<FinPalette>()!;
    final btnStyle = preview.filledButtonTheme.style;
    final btnBg = btnStyle?.backgroundColor?.resolve({}) ?? preview.colorScheme.primary;
    final btnFg = btnStyle?.foregroundColor?.resolve({}) ?? preview.colorScheme.onPrimary;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? scheme.primary : null),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(theme.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(theme.description, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            // Mini maqueta: fondo, tarjeta principal y montos.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: preview.colorScheme.surface, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: preview.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(6)),
                  child: Text('\$650', style: TextStyle(color: preview.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                Text('+\$400 ', style: TextStyle(color: fin.income, fontWeight: FontWeight.w700, fontSize: 12)),
                Text('-\$750', style: TextStyle(color: fin.pending, fontWeight: FontWeight.w700, fontSize: 12)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: btnBg, borderRadius: BorderRadius.circular(20)),
                  child: Text('Pagar', style: TextStyle(color: btnFg, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (final c in theme.swatch)
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ReminderSettings extends StatelessWidget {
  const _ReminderSettings();

  @override
  Widget build(BuildContext context) {
    final n = NotificationScope.of(context);
    if (n == null) return const SizedBox.shrink();
    final s = n.settings;
    Future<void> set(ReminderSettings v) => n.updateSettings(v);
    const options = [(7, '1 semana antes'), (2, '2 días antes'), (1, '1 día antes'), (0, 'El día del pago')];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            title: const Text('Recordatorios de pagos'),
            subtitle: Text(n.supportsSystemNotifications
                ? 'Notificaciones en este teléfono, aunque la app esté cerrada.'
                : 'En la web los avisos aparecen en la campana. Las notificaciones del sistema están en la app de Android.'),
            value: s.enabled,
            onChanged: (v) => set(s.copyWith(enabled: v)),
          ),
          if (s.enabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Avisar', style: Theme.of(context).textTheme.labelLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final (d, label) in options)
                  FilterChip(
                    label: Text(label),
                    selected: s.daysBefore.contains(d),
                    onSelected: (on) {
                      final next = {...s.daysBefore};
                      on ? next.add(d) : next.remove(d);
                      set(s.copyWith(daysBefore: next.toList()..sort((a, b) => b.compareTo(a))));
                    },
                  ),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Hora del aviso'),
              trailing: Text(TimeOfDay(hour: s.hour, minute: s.minute).format(context),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.hour, minute: s.minute));
                if (t != null) set(s.copyWith(hour: t.hour, minute: t.minute));
              },
            ),
            SwitchListTile(
              title: const Text('Recordar ingresos previstos'),
              subtitle: const Text('El día que esperas un ingreso, para que lo confirmes.'),
              value: s.incomeReminders,
              onChanged: (v) => set(s.copyWith(incomeReminders: v)),
            ),
            if (n.supportsSystemNotifications) ...[
              ListTile(
                dense: true,
                leading: Icon(
                  n.permissionGranted == true ? Icons.check_circle : Icons.error_outline,
                  color: n.permissionGranted == true ? FinColors.of(context).income : Theme.of(context).colorScheme.error,
                ),
                title: Text(n.initError != null
                    ? 'No se pudo iniciar el sistema de notificaciones'
                    : (n.permissionGranted == true ? 'Notificaciones permitidas en este teléfono' : 'Las notificaciones están desactivadas')),
                subtitle: n.initError != null ? Text(n.initError!, maxLines: 3, overflow: TextOverflow.ellipsis) : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (n.permissionGranted != true)
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await n.requestPermission();
                        if (context.mounted && !ok) {
                          showMessage(
                              context,
                              n.initError != null
                                  ? 'El sistema de notificaciones no arrancó. Abre los ajustes de notificaciones del teléfono.'
                                  : 'Android no dio el permiso. Usa «Abrir ajustes de notificaciones» y activa las de Drago.',
                              error: true);
                        }
                      },
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Permitir notificaciones'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await n.showTest();
                      if (context.mounted) showMessage(context, 'Notificación de prueba enviada');
                    },
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Probar notificación'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await n.openSystemSettings();
                      // Al volver, se revisa otra vez el permiso.
                      await Future<void>.delayed(const Duration(milliseconds: 500));
                      await n.refreshPermission();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Abrir ajustes de notificaciones'),
                  ),
                ]),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    final lock = AppLockScope.of(context);
    return Card(
      child: Column(children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('Bloquear Drago'),
          subtitle: Text(!lock.enabled
              ? 'Pide desbloquear al abrir la app y al volver después de 1 minuto.'
              : lock.method == LockMethod.device
                  ? 'Con el bloqueo del teléfono (huella, rostro, PIN o patrón).'
                  : 'Con PIN de Drago.'),
          value: lock.enabled,
          onChanged: (on) async {
            if (!on) {
              final ok = lock.method == LockMethod.device ? await lock.unlockWithDevice() : await _askPin(context, lock, verify: true);
              if (ok) await lock.disable();
              return;
            }
            if (await lock.deviceAuthAvailable()) {
              final ok = await lock.enableDevice();
              if (!ok && context.mounted) showMessage(context, 'No se pudo verificar. El bloqueo no se activó.', error: true);
            } else if (context.mounted) {
              await _askPin(context, lock, verify: false);
            }
          },
        ),
        if (lock.enabled && lock.method == LockMethod.pin)
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Cambiar PIN'),
            onTap: () async {
              if (await _askPin(context, lock, verify: true) && context.mounted) await _askPin(context, lock, verify: false);
            },
          ),
        if (!lock.deviceAuthPlatform)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('En la web el bloqueo evita que alguien vea tus datos al abrir la página en este navegador. '
                'Cierra sesión en computadoras compartidas.', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }

  /// verify=true: pide el PIN actual. verify=false: crea uno nuevo (dos veces).
  Future<bool> _askPin(BuildContext context, AppLock lock, {required bool verify}) async {
    final a = TextEditingController(), b = TextEditingController();
    String? error;
    final result = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text(verify ? 'Escribe tu PIN' : 'Crea un PIN de Drago'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!verify) const Text('De 4 a 8 números. Por seguridad no se puede recuperar si lo olvidas.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: a,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder(), counterText: ''),
            ),
            if (!verify) ...[
              const SizedBox(height: 8),
              TextField(
                controller: b,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Repite el PIN', border: OutlineInputBorder(), counterText: ''),
              ),
            ],
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(d).colorScheme.error))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (verify) {
                  if (lock.checkPin(a.text)) {
                    Navigator.pop(d, true);
                  } else {
                    setState(() => error = 'PIN incorrecto');
                  }
                  return;
                }
                if (a.text.length < 4) return setState(() => error = 'Usa al menos 4 números');
                if (a.text != b.text) return setState(() => error = 'Los PIN no coinciden');
                Navigator.pop(d, true);
              },
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
    if (result == true && !verify) {
      await lock.enablePin(a.text);
      if (context.mounted) showMessage(context, 'Bloqueo activado');
    }
    return result == true;
  }
}
