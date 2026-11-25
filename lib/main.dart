import 'package:material_ui/material_ui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'data/app_state.dart';
import 'data/storage.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'es_MX';
  await initializeDateFormatting('es_MX');
  final state = await AppState.open(PrefsLedgerStorage());
  runApp(FinanSyncApp(state: state));
}

class FinanSyncApp extends StatelessWidget {
  final AppState state;
  const FinanSyncApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F6F5C);
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'FinanSync',
        debugShowCheckedModeBanner: false,
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es', 'MX'), Locale('es'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
        home: const AppShell(),
      ),
    );
  }
}
