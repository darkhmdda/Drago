import 'package:material_ui/material_ui.dart';

import 'calendar_screen.dart';
import 'debts_screen.dart';
import 'dialogs.dart';
import 'home_screen.dart';
import 'movements_screen.dart';
import 'settings_screen.dart';
import 'sync_widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _titles = ['Inicio', 'Deudas y pagos', 'Calendario financiero', 'Movimientos', 'Configuración'];
  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Inicio'),
    (Icons.credit_card_outlined, Icons.credit_card, 'Deudas'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Calendario'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Movimientos'),
    (Icons.settings_outlined, Icons.settings, 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = [
      HomeScreen(onOpenDebts: () => setState(() => _index = 1), onOpenCalendar: () => setState(() => _index = 2)),
      const DebtsScreen(),
      const CalendarScreen(),
      const MovementsScreen(),
      const SettingsScreen(),
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
        actions: [SyncIndicator(onTap: () => setState(() => _index = 4)), const SizedBox(width: 8)],
      ),
      floatingActionButton: fab,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
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
