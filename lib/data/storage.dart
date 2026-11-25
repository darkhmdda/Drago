import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ledger.dart';

/// Almacenamiento local (funciona en Android y en navegador).
///
/// Guarda una instantánea completa en cada cambio confirmado. Más adelante se
/// sustituirá/complementará con SQLite local + sincronización con Supabase.
abstract class LedgerStorage {
  Future<Ledger?> load();
  Future<void> save(Ledger ledger);
}

class PrefsLedgerStorage implements LedgerStorage {
  static const _key = 'finansync.ledger.v1';
  static const _backupKey = 'finansync.ledger.v1.previous';

  @override
  Future<Ledger?> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_key, _backupKey]) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        return Ledger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Si la copia principal está dañada, se intenta con la anterior.
      }
    }
    return null;
  }

  @override
  Future<void> save(Ledger ledger) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_key);
    if (previous != null) await prefs.setString(_backupKey, previous);
    await prefs.setString(_key, jsonEncode(ledger.toJson()));
  }
}

class MemoryLedgerStorage implements LedgerStorage {
  String? data;
  @override
  Future<Ledger?> load() async => data == null ? null : Ledger.fromJson(jsonDecode(data!));
  @override
  Future<void> save(Ledger ledger) async => data = jsonEncode(ledger.toJson());
}
