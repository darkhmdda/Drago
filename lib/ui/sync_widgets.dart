import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../data/sync_scope.dart';
import '../data/sync_service.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import 'auth_screen.dart';
import 'common.dart';

String _ago(DateTime? t) {
  if (t == null) return 'nunca';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'hace un momento';
  if (d.inHours < 1) return 'hace ${d.inMinutes} min';
  if (d.inDays < 1) return 'hace ${d.inHours} h';
  return DateFormat("d MMM, HH:mm", 'es_MX').format(t);
}

(IconData, String) syncLook(SyncService s) => switch (s.status) {
      SyncStatus.signedOut => (Icons.cloud_off_outlined, 'Solo en este dispositivo'),
      SyncStatus.idle => (Icons.cloud_done_outlined, 'Sincronizado ${_ago(s.lastSync)}'),
      SyncStatus.syncing => (Icons.cloud_sync_outlined, 'Sincronizando…'),
      SyncStatus.pending => (Icons.cloud_upload_outlined, 'Cambios pendientes de subir'),
      SyncStatus.offline => (Icons.cloud_off, s.lastError ?? 'Sin conexión'),
      SyncStatus.conflict => (Icons.sync_problem, 'Hay cambios en otro dispositivo'),
    };

/// Icono de estado en la barra superior.
class SyncIndicator extends StatelessWidget {
  final VoidCallback onTap;
  const SyncIndicator({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = SyncScope.of(context).sync;
    if (s == null) return const SizedBox.shrink();
    final (icon, text) = syncLook(s);
    final scheme = Theme.of(context).colorScheme;
    final color = switch (s.status) {
      SyncStatus.conflict || SyncStatus.offline => scheme.error,
      SyncStatus.idle => FinColors.of(context).income,
      _ => null,
    };
    return IconButton(tooltip: text, icon: Icon(icon, color: color), onPressed: onTap);
  }
}

/// Aviso cuando la nube y este dispositivo tienen cambios distintos.
class ConflictBanner extends StatelessWidget {
  const ConflictBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SyncScope.of(context).sync;
    if (s == null || s.conflict == null) return const SizedBox.shrink();
    return MaterialBanner(
      leading: const Icon(Icons.sync_problem),
      content: const Text('Tus datos cambiaron en otro dispositivo y también aquí. Elige qué copia conservar; '
          'no se perderá nada hasta que decidas.'),
      actions: [TextButton(onPressed: () => showConflictDialog(context), child: const Text('Revisar'))],
    );
  }
}

Future<void> showConflictDialog(BuildContext context) async {
  final s = SyncScope.of(context).sync!;
  final c = s.conflict;
  if (c == null) return;
  final local = AppScope.of(context).ledger;

  Widget summary(String title, Ledger l, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(title, style: const TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 6),
            Text('Total disponible: ${formatMoney(l.totalAvailable)}'),
            Text('Movimientos: ${l.transactions.length}'),
            Text('Deudas: ${l.debts.length} · pendiente ${formatMoney(l.totalPendingDebt)}'),
            if (l.auditLog.isNotEmpty) Text('Último cambio: ${l.auditLog.last.action} (${_ago(l.auditLog.last.at.toLocal())})'),
          ]),
        ),
      );

  final keepLocal = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('¿Qué copia conservar?'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            summary('Este dispositivo', local, Icons.phone_android),
            summary('Nube (otro dispositivo)', c.remote, Icons.cloud_outlined),
            const SizedBox(height: 8),
            const Text('La copia que no elijas se reemplaza. Si tienes dudas, copia antes un respaldo desde Ajustes.',
                style: TextStyle(fontSize: 13)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Decidir después')),
        OutlinedButton(onPressed: () => Navigator.pop(d, false), child: const Text('Usar la de la nube')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Usar la de este dispositivo')),
      ],
    ),
  );
  if (keepLocal == null || !context.mounted) return;
  final sure = await confirm(
    context,
    'Confirmar',
    keepLocal
        ? 'Los datos de este dispositivo reemplazarán a los de la nube y de tus otros dispositivos.'
        : 'Los datos de la nube reemplazarán a los de este dispositivo.',
    danger: true,
  );
  if (sure) await s.resolveConflict(keepThisDevice: keepLocal);
}

/// Sección «Cuenta y sincronización» de Ajustes.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SyncScope.of(context);
    final s = scope.sync;
    if (s == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Sincronización no disponible'),
          subtitle: Text('No se pudo iniciar la conexión con la nube. Tus datos siguen guardados en este dispositivo.'),
        ),
      );
    }
    final (icon, text) = syncLook(s);
    final email = s.remote.userEmail;
    if (s.status == SyncStatus.signedOut) {
      return Card(
        child: Column(children: [
          const ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Solo en este dispositivo'),
            subtitle: Text('Inicia sesión para respaldar tus datos en la nube y usarlos en la computadora y el teléfono.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen())),
                icon: const Icon(Icons.login),
                label: const Text('Iniciar sesión o crear cuenta'),
              ),
            ),
          ),
        ]),
      );
    }
    return Card(
      child: Column(children: [
        ListTile(leading: const Icon(Icons.account_circle_outlined), title: Text(email ?? 'Sesión iniciada'), subtitle: const Text('Cuenta')),
        ListTile(
          leading: Icon(icon),
          title: Text(text),
          subtitle: s.status == SyncStatus.offline ? const Text('Tus cambios se guardan aquí y se subirán al volver la conexión.') : null,
        ),
        if (s.conflict != null)
          ListTile(
            leading: const Icon(Icons.sync_problem),
            title: const Text('Resolver diferencia entre dispositivos'),
            onTap: () => showConflictDialog(context),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: s.status == SyncStatus.syncing ? null : s.sync,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar ahora'),
            ),
            TextButton.icon(onPressed: () => _signOut(context), icon: const Icon(Icons.logout), label: const Text('Cerrar sesión')),
          ]),
        ),
      ]),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final scope = SyncScope.of(context);
    final s = scope.sync!;
    final pending = s.hasPendingChanges;
    final wipe = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: Text(pending
            ? 'Hay cambios que aún no se subieron a la nube. Si borras los datos de este dispositivo, esos cambios se perderán.'
            : 'Tus datos están en la nube. ¿Quieres conservar también una copia en este dispositivo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cerrar y borrar de aquí')),
          FilledButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cerrar y conservar')),
        ],
      ),
    );
    if (wipe == null || !context.mounted) return;
    final app = AppScope.of(context);
    await scope.auth!.signOut();
    if (wipe) {
      await app.replaceFromSync(Ledger.withDefaults());
    }
    await s.forgetUser();
    if (context.mounted) showMessage(context, 'Sesión cerrada');
  }
}

/// Engrane de Ajustes; en el teléfono lleva un punto si la sincronización
/// necesita atención (conflicto, sin conexión o cambios pendientes).
class SettingsButton extends StatelessWidget {
  final bool showSyncDot;
  final VoidCallback onTap;
  const SettingsButton({super.key, required this.showSyncDot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = SyncScope.of(context).sync;
    final scheme = Theme.of(context).colorScheme;
    final status = s?.status;
    final Color? dot = !showSyncDot || status == null
        ? null
        : switch (status) {
            SyncStatus.conflict || SyncStatus.offline => scheme.error,
            _ => null,
          };
    return IconButton(
      tooltip: s == null || !showSyncDot ? 'Ajustes' : 'Ajustes · ${syncLook(s).$2}',
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: dot != null,
        smallSize: 9,
        backgroundColor: dot,
        child: const Icon(Icons.settings_outlined),
      ),
    );
  }
}
