import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ledger.dart';
import 'app_state.dart';

/// La nube tiene una versión más nueva que la que este dispositivo conoce.
class SyncConflict implements Exception {
  const SyncConflict();
}

/// Sin sesión, sin red o error del servidor.
class SyncFailure implements Exception {
  final String message;
  const SyncFailure(this.message);
  @override
  String toString() => message;
}

/// Acceso remoto (Supabase en producción; un falso en las pruebas).
abstract class SyncRemote {
  /// Id del usuario con sesión iniciada, o null.
  String? get userId;
  String? get userEmail;

  /// Devuelve todos los datos del usuario (con 'syncVersion').
  Future<Map<String, dynamic>> pull();

  /// Sube todos los datos. Lanza [SyncConflict] si [baseVersion] no es la actual.
  Future<int> push(int baseVersion, Map<String, dynamic> data);
}

enum SyncStatus { signedOut, idle, syncing, pending, offline, conflict }

/// Datos de la nube que chocan con cambios locales, para que el usuario elija.
class ConflictInfo {
  final Ledger remote;
  final int remoteVersion;
  const ConflictInfo(this.remote, this.remoteVersion);
}

/// Sincronización local-primero:
/// - Todo se guarda primero en el dispositivo; la app funciona sin conexión.
/// - Cada cambio local marca "pendiente" y se sube unos segundos después.
/// - Si otro dispositivo subió cambios y aquí no hay nada pendiente, se
///   descargan. Si ambos cambiaron, NO se pisa nada: se pregunta al usuario.
class SyncService extends ChangeNotifier {
  final AppState app;
  final SyncRemote remote;
  final Duration debounce;

  /// Prefijo de las claves locales (permite simular varios dispositivos en pruebas).
  final String keyPrefix;

  SyncService(this.app, this.remote, {this.debounce = const Duration(seconds: 2), this.keyPrefix = 'drago.sync'});

  String get _kBase => '$keyPrefix.baseVersion';
  String get _kDirty => '$keyPrefix.dirty';
  String get _kUser => '$keyPrefix.userId';
  String get _kLast => '$keyPrefix.lastSync';

  int _base = 0;
  bool _dirty = false;
  String? _syncedUser;
  DateTime? lastSync;
  String? lastError;
  ConflictInfo? conflict;
  bool _busy = false;
  bool _again = false;
  Timer? _timer;

  SyncStatus get status {
    if (remote.userId == null) return SyncStatus.signedOut;
    if (conflict != null) return SyncStatus.conflict;
    if (_busy) return SyncStatus.syncing;
    if (lastError != null) return SyncStatus.offline;
    if (_dirty) return SyncStatus.pending;
    return SyncStatus.idle;
  }

  bool get hasPendingChanges => _dirty;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _base = p.getInt(_kBase) ?? 0;
    _dirty = p.getBool(_kDirty) ?? true; // datos nunca subidos = pendientes
    _syncedUser = p.getString(_kUser);
    final last = p.getString(_kLast);
    lastSync = last == null ? null : DateTime.tryParse(last);
    app.onLocalChange = _onLocalChange;
  }

  Future<void> _saveMeta() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kBase, _base);
    await p.setBool(_kDirty, _dirty);
    if (_syncedUser == null) {
      await p.remove(_kUser);
    } else {
      await p.setString(_kUser, _syncedUser!);
    }
    if (lastSync != null) await p.setString(_kLast, lastSync!.toIso8601String());
  }

  void _onLocalChange() {
    _dirty = true;
    _saveMeta();
    notifyListeners();
    if (remote.userId == null) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => sync());
  }

  /// Sin movimientos, deudas ni previstos: nada que valga la pena conservar.
  static bool isEmptyLedger(Ledger l) =>
      l.transactions.isEmpty && l.debts.isEmpty && l.scheduledItems.isEmpty && l.recurrences.isEmpty;

  /// Sincroniza ahora. Es seguro llamarla muchas veces.
  Future<void> sync() async {
    final user = remote.userId;
    if (user == null) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      // Otro usuario (o primera vez) en este dispositivo: la versión local no aplica.
      if (_syncedUser != user) {
        _syncedUser = user;
        _base = 0;
        _dirty = !isEmptyLedger(app.ledger);
      }
      final data = await remote.pull();
      final remoteVersion = (data['syncVersion'] as num?)?.toInt() ?? 0;

      if (remoteVersion == _base) {
        if (_dirty) await _push(remoteVersion);
      } else if (remoteVersion > _base) {
        final remoteLedger = Ledger.fromJson(data);
        if (!_dirty || isEmptyLedger(app.ledger)) {
          await app.replaceFromSync(remoteLedger);
          _base = remoteVersion;
          _dirty = false;
        } else {
          conflict = ConflictInfo(remoteLedger, remoteVersion);
        }
      } else {
        // La nube quedó en una versión anterior (por ejemplo, se restauró): subir lo local.
        _base = remoteVersion;
        await _push(remoteVersion);
      }
      if (conflict == null) lastSync = DateTime.now();
      lastError = null;
    } on SyncConflict {
      _again = true; // alguien subió justo antes: repetir para detectar el conflicto
    } on SyncFailure catch (e) {
      lastError = e.message;
    } on FinanceException catch (e) {
      lastError = 'Los datos de la nube no son válidos: ${e.message}';
    } catch (e) {
      lastError = 'No se pudo sincronizar: $e';
    } finally {
      _busy = false;
      await _saveMeta();
      notifyListeners();
    }
    if (_again && conflict == null) {
      _again = false;
      await sync();
    }
  }

  Future<void> _push(int base) async {
    _base = await remote.push(base, app.ledger.toJson());
    _dirty = false;
  }

  /// Resuelve un conflicto conservando una de las dos copias.
  Future<void> resolveConflict({required bool keepThisDevice}) async {
    final c = conflict;
    if (c == null) return;
    conflict = null;
    if (keepThisDevice) {
      _base = c.remoteVersion;
      _dirty = true;
    } else {
      await app.replaceFromSync(c.remote);
      _base = c.remoteVersion;
      _dirty = false;
    }
    await _saveMeta();
    notifyListeners();
    await sync();
  }

  /// Llamar al cerrar sesión.
  Future<void> forgetUser() async {
    _timer?.cancel();
    _syncedUser = null;
    _base = 0;
    _dirty = true;
    conflict = null;
    lastError = null;
    await _saveMeta();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
