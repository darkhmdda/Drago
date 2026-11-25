import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/app_state.dart';
import 'data/storage.dart';
import 'data/supabase_remote.dart';
import 'data/sync_scope.dart';
import 'data/sync_service.dart';
import 'ui/shell.dart';
import 'ui/themes.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'es_MX';
  await initializeDateFormatting('es_MX');
  final state = await AppState.open(PrefsLedgerStorage());
  final theme = await ThemeController.load();

  // La nube es opcional: si no se puede iniciar, la app funciona solo en local.
  SyncService? sync;
  AuthService? auth;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    final client = Supabase.instance.client;
    auth = AuthService(client.auth);
    sync = SyncService(state, SupabaseSyncRemote(client));
    await sync.init();
    _wireSync(client, sync);
  } catch (e) {
    debugPrint('Sincronización no disponible: $e');
  }

  runApp(DragoApp(state: state, theme: theme, sync: sync, auth: auth));
}

void _wireSync(SupabaseClient client, SyncService sync) {
  client.auth.onAuthStateChange.listen((data) {
    switch (data.event) {
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
        if (data.session != null) sync.sync();
      case AuthChangeEvent.signedOut:
        sync.forgetUser();
      case AuthChangeEvent.passwordRecovery:
        _askNewPassword(client);
      default:
        break;
    }
  });
  // Revisar cambios de otros dispositivos al volver a la app y cada 2 minutos.
  AppLifecycleListener(onResume: sync.sync);
  Timer.periodic(const Duration(minutes: 2), (_) => sync.sync());
}

/// El usuario abrió el enlace de «Olvidé mi contraseña».
Future<void> _askNewPassword(SupabaseClient client) async {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  final c = TextEditingController();
  final pass = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (d) => AlertDialog(
      title: const Text('Nueva contraseña'),
      content: TextField(
        controller: c,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Al menos 8 caracteres'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(d, c.text),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (pass == null || pass.length < 8) return;
  try {
    await client.auth.updateUser(UserAttributes(password: pass));
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('Contraseña actualizada')));
    }
  } on AuthException catch (e) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class DragoApp extends StatelessWidget {
  final AppState state;
  final ThemeController theme;
  final SyncService? sync;
  final AuthService? auth;
  const DragoApp({
    super.key,
    required this.state,
    required this.theme,
    this.sync,
    this.auth,
  });

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: SyncScope(
        sync: sync,
        auth: auth,
        child: ThemeScope(
          controller: theme,
          child: ListenableBuilder(
            listenable: theme,
            builder: (context, _) => MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Drago',
              debugShowCheckedModeBanner: false,
              locale: const Locale('es', 'MX'),
              supportedLocales: const [
                Locale('es', 'MX'),
                Locale('es'),
                Locale('en'),
              ],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: theme.theme.data,
              home: const AppShell(),
            ),
          ),
        ),
      ),
    );
  }
}
