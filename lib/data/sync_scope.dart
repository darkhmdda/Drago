import 'package:flutter/widgets.dart';

import 'supabase_remote.dart';
import 'sync_service.dart';

/// Da acceso a la sincronización y a la autenticación desde la interfaz.
/// [sync] es null si la nube no está configurada (la app funciona igual).
class SyncScope extends InheritedNotifier<SyncService> {
  final AuthService? auth;
  const SyncScope({super.key, required SyncService? sync, required this.auth, required super.child}) : super(notifier: sync);

  static SyncScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SyncScope>()!;
  SyncService? get sync => notifier;
}
