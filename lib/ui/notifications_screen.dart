import 'package:material_ui/material_ui.dart';

import '../data/notification_service.dart';
import '../domain/money.dart';
import '../domain/reminders.dart';
import 'common.dart';
import 'scheduled_dialogs.dart';

class NotificationScope extends InheritedNotifier<NotificationService> {
  const NotificationScope({super.key, required NotificationService? service, required super.child}) : super(notifier: service);
  static NotificationService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>()?.notifier;
}

/// Campana de la barra superior con el número de avisos sin ver.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final n = NotificationScope.of(context);
    if (n == null) return const SizedBox.shrink();
    final count = n.unseenCount;
    return IconButton(
      tooltip: 'Notificaciones',
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(count > 0 ? Icons.notifications_active_outlined : Icons.notifications_none),
      ),
    );
  }
}

/// Centro de notificaciones: recordatorios que ya tocaba mostrar de pagos e
/// ingresos que siguen pendientes. Lo pagado o recibido desaparece solo.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationService? _service = NotificationScope.of(context);
  late final Set<String> _unseenAtOpen = {
    for (final r in _service?.inbox ?? const <Reminder>[])
      if (!_service!.isSeen(r)) r.key,
  };

  @override
  void initState() {
    super.initState();
    // Al abrir el centro, todo queda como visto (se resaltan los nuevos).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unseenAtOpen; // fija cuáles eran nuevos antes de marcarlos
      _service?.markAllSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = NotificationScope.of(context);
    final inbox = n?.inbox ?? const <Reminder>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: PageBody(children: [
        if (n != null && !n.settings.enabled)
          const Card(child: ListTile(leading: Icon(Icons.notifications_off_outlined), title: Text('Los recordatorios están desactivados en Ajustes.'))),
        if (inbox.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No tienes avisos pendientes.\nAquí aparecerán los recordatorios de tus pagos.', textAlign: TextAlign.center)),
          ),
        for (final r in inbox) _ReminderTile(r, isNew: _unseenAtOpen.contains(r.key)),
      ]),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final Reminder r;
  final bool isNew;
  const _ReminderTile(this.r, {required this.isNew});

  @override
  Widget build(BuildContext context) {
    final e = r.event;
    final color = eventColor(context, e);
    final title = e.overdue ? (e.isIncome ? 'Ingreso sin confirmar: ${e.title}' : 'Vencido: ${e.title}') : r.title;
    return Card(
      child: ListTile(
        onTap: () => showEventActions(context, e),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(eventIcon(e), color: color, size: 20)),
        title: Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontWeight: isNew ? FontWeight.w700 : FontWeight.w500))),
          if (isNew) StatusChip('Nuevo', Theme.of(context).colorScheme.primary),
        ]),
        subtitle: Text('${fmtShortDate(e.date)} · ${e.statusLabel} · ${formatMoney(e.amount)}'),
      ),
    );
  }
}
