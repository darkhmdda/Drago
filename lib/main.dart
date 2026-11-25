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
import 'data/notification_service.dart';
import 'ui/notifications_screen.dart';
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
    final remote = SupabaseSyncRemote(client);
    sync = SyncService(state, remote);
    await sync.init();
    _wireSync(client, remote, sync);
  } catch (e) {
    debugPrint('Sincronización no disponible: $e');
  }

  // Recordatorios: si fallan, la app sigue funcionando sin ellos.
  NotificationService? notifications = NotificationService(state);
  try {
    await notifications.init();
  } catch (e) {
    debugPrint('Recordatorios no disponibles: $e');
    notifications = null;
  }

  runApp(
    DragoApp(
      state: state,
      theme: theme,
      sync: sync,
      auth: auth,
      notifications: notifications,
    ),
  );
}

void _wireSync(
  SupabaseClient client,
  SupabaseSyncRemote remote,
  SyncService sync,
) {
  client.auth.onAuthStateChange.listen((data) {
    switch (data.event) {
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
        if (data.session != null) {
          sync.sync();
          // Aviso inmediato cuando otro dispositivo sube cambios.
          remote.listen(sync.checkRemote);
        }
      case AuthChangeEvent.signedOut:
        remote.stopListening();
        sync.forgetUser();
      case AuthChangeEvent.passwordRecovery:
        _askNewPassword(client);
      default:
        break;
    }
  });
  // Respaldo del aviso en tiempo real: al volver a la app y cada 30 segundos
  // se consulta solo el número de versión (se descarga todo únicamente si cambió).
  AppLifecycleListener(onResume: sync.checkRemote);
  Timer.periodic(const Duration(seconds: 30), (_) => sync.checkRemote());
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
      ScaffoldMessenger.of(ctx)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class DragoApp extends StatelessWidget {
  final AppState state;
  final ThemeController theme;
  final SyncService? sync;
  final AuthService? auth;
  final NotificationService? notifications;
  const DragoApp({
    super.key,
    required this.state,
    required this.theme,
    this.sync,
    this.auth,
    this.notifications,
  });

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: SyncScope(
        sync: sync,
        auth: auth,
        child: NotificationScope(
          service: notifications,
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
      ),
    );
  }
}
