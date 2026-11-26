import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../data/widget_service.dart';

import 'assistant_screen.dart';
import 'calendar_screen.dart';
import 'debts_screen.dart';
import 'dialogs.dart';
import 'home_screen.dart';
import 'movements_screen.dart';
import 'notifications_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sync_widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _calendarFocus = ValueNotifier<DateTime?>(null);
  WidgetService? _widget;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final w = WidgetScope.of(context);
    if (w != _widget) {
      _widget?.launches.removeListener(_onWidgetLaunch);
      _widget = w;
      w?.launches.addListener(_onWidgetLaunch);
      if (w?.launches.value != null) WidgetsBinding.instance.addPostFrameCallback((_) => _onWidgetLaunch());
    }
  }

  @override
  void dispose() {
    _widget?.launches.removeListener(_onWidgetLaunch);
    super.dispose();
  }

  /// Toque en el widget de la pantalla de inicio: abre el día o la deuda.
  void _onWidgetLaunch() {
    final uri = _widget?.launches.value;
    if (uri == null || !mounted) return;
    _widget!.launches.value = null;
    final date = DateTime.tryParse(uri.queryParameters['date'] ?? '');
    Navigator.of(context).popUntil((r) => r.isFirst);
    final debtId = uri.queryParameters['id'];
    if (uri.host == 'debt' && debtId != null && AppScope.of(context).ledger.debts.any((d) => d.id == debtId)) {
      setState(() => _index = 1);
      Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debtId)));
    } else {
      setState(() => _index = 2);
      _calendarFocus.value = null;
      _calendarFocus.value = date ?? DateTime.now();
    }
  }

  static const _titles = ['Inicio', 'Deudas y pagos', 'Calendario', 'Movimientos', 'Reportes'];
  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Inicio'),
    (Icons.credit_card_outlined, Icons.credit_card, 'Deudas'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Calendario'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Movimientos'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Reportes'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = [
      HomeScreen(onOpenDebts: () => setState(() => _index = 1), onOpenCalendar: () => setState(() => _index = 2)),
      const DebtsScreen(),
      CalendarScreen(focus: _calendarFocus),
      const MovementsScreen(),
      const ReportsScreen(),
    ];
    final fab = switch (_index) {
      1 => FloatingActionButton.extended(
          onPressed: () => showDebtForm(context), icon: const Icon(Icons.add), label: const Text('Nueva deuda')),
      4 => null,
      _ => FloatingActionButton.extended(
          onPressed: () => showQuickActions(context), icon: const Icon(Icons.add), label: const Text('Registrar')),
    };

    final body = Column(children: [
      const ConflictBanner(),
      Expanded(child: IndexedStack(index: _index, children: pages)),
    ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Asistente',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantScreen())),
          ),
          const NotificationBell(),
          // En pantallas anchas se muestra el estado de la nube; en el teléfono
          // va como un punto sobre el engrane (solo si hay algo que atender).
          if (wide) SyncIndicator(onTap: () => openSettings(context)),
          SettingsButton(showSyncDot: !wide, onTap: () => openSettings(context)),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: fab,
      bottomNavigationBar: wide
          ? null
          // Etiquetas compactas: con letra grande del sistema, «Movimientos»
          // se partía en dos líneas.
          : MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.resolveWith(
                    (states) => TextStyle(
                      fontSize: 11,
                      letterSpacing: 0,
                      overflow: TextOverflow.ellipsis,
                      fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
                  ],
                ),
              ),
            ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
    );
  }
}

/// Ajustes se abre como pantalla aparte (engrane de la barra superior).
void openSettings(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Ajustes')), body: const SettingsScreen())),
    );
