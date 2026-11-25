import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_service.dart';

/// Implementación de [SyncRemote] con Supabase (funciones pull_ledger /
/// push_ledger de supabase/migrations/20261126000000_sync.sql).
class SupabaseSyncRemote implements SyncRemote {
  final SupabaseClient client;
  SupabaseSyncRemote(this.client);

  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  String? get userEmail => client.auth.currentUser?.email;

  static String get deviceName => kIsWeb ? 'web' : defaultTargetPlatform.name;

  @override
  Future<Map<String, dynamic>> pull() async {
    try {
      final r = await client.rpc('pull_ledger');
      return Map<String, dynamic>.from(r as Map);
    } on PostgrestException catch (e) {
      throw SyncFailure(_explain(e));
    } on AuthException catch (e) {
      throw SyncFailure('Sesión no válida: ${e.message}');
    } catch (_) {
      throw const SyncFailure('Sin conexión. Los cambios se guardan aquí y se subirán después.');
    }
  }

  @override
  Future<int> push(int baseVersion, Map<String, dynamic> data) async {
    try {
      final r = await client.rpc('push_ledger', params: {
        'p_base_version': baseVersion,
        'p_data': data,
        'p_device': deviceName,
      });
      return (r as num).toInt();
    } on PostgrestException catch (e) {
      if (e.code == 'P0409') throw const SyncConflict();
      throw SyncFailure(_explain(e));
    } on AuthException catch (e) {
      throw SyncFailure('Sesión no válida: ${e.message}');
    } catch (_) {
      throw const SyncFailure('Sin conexión. Los cambios se guardan aquí y se subirán después.');
    }
  }

  static String _explain(PostgrestException e) {
    if (e.code == 'PGRST202' || e.message.contains('Could not find the function')) {
      return 'La base de datos aún no está preparada: falta ejecutar los scripts de supabase/migrations.';
    }
    return 'Error del servidor: ${e.message}';
  }
}

/// Inicio de sesión con correo y contraseña. Devuelve mensajes en español.
class AuthService {
  final GoTrueClient auth;
  AuthService(this.auth);

  Future<void> signIn(String email, String password) async {
    try {
      await auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw AuthFailure(_translate(e.message));
    } catch (_) {
      throw const AuthFailure('No hay conexión con el servidor.');
    }
  }

  /// Devuelve true si la cuenta quedó lista; false si hay que confirmar el correo.
  Future<bool> signUp(String email, String password) async {
    try {
      final r = await auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: kIsWeb ? _appUrl : null,
      );
      return r.session != null;
    } on AuthException catch (e) {
      throw AuthFailure(_translate(e.message));
    } catch (_) {
      throw const AuthFailure('No hay conexión con el servidor.');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await auth.resetPasswordForEmail(email.trim(), redirectTo: kIsWeb ? _appUrl : null);
    } on AuthException catch (e) {
      throw AuthFailure(_translate(e.message));
    }
  }

  Future<void> signOut() => auth.signOut();

  /// Dirección de la app web incluida la ruta (por ejemplo, GitHub Pages
  /// la sirve en https://usuario.github.io/Drago/).
  static String get _appUrl => '${Uri.base.origin}${Uri.base.path}';

  static String _translate(String m) {
    final s = m.toLowerCase();
    if (s.contains('failed to fetch') || s.contains('clientexception') || s.contains('socketexception') ||
        s.contains('failed host lookup') || s.contains('connection')) {
      return 'No hay conexión con el servidor. Revisa tu internet e inténtalo de nuevo.';
    }
    if (s.contains('invalid login credentials')) return 'Correo o contraseña incorrectos.';
    if (s.contains('email not confirmed')) return 'Aún no confirmas tu correo. Abre el enlace que te enviamos.';
    if (s.contains('already registered') || s.contains('already been registered')) {
      return 'Ya existe una cuenta con ese correo. Inicia sesión.';
    }
    if (s.contains('password should be at least')) return 'La contraseña debe tener al menos 6 caracteres.';
    if (s.contains('rate limit')) return 'Demasiados intentos. Espera unos minutos.';
    if (s.contains('signups not allowed')) return 'El registro de cuentas nuevas está desactivado.';
    if (s.contains('invalid') && s.contains('email')) return 'El correo no es válido.';
    return m;
  }
}

class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}
