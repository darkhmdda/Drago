import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../domain/ledger.dart';
import 'storage.dart';

/// Estado de la aplicación. Toda modificación pasa por [run], que ejecuta la
/// operación sobre una copia y solo la confirma (y guarda) si tuvo éxito.
class AppState extends ChangeNotifier {
  final LedgerStorage storage;
  Ledger _ledger;

  AppState(this.storage, this._ledger);

  /// Se llama después de cada cambio hecho por el usuario en este dispositivo
  /// (lo usa la sincronización para saber que hay algo que subir).
  void Function()? onLocalChange;

  Ledger get ledger => _ledger;

  static Future<AppState> open(LedgerStorage storage) async {
    final loaded = await storage.load();
    final ledger = loaded ?? Ledger.withDefaults();
    if (loaded == null) await storage.save(ledger);
    return AppState(storage, ledger);
  }

  /// Ejecuta una operación de forma atómica. Lanza [FinanceException] si falla,
  /// en cuyo caso los datos no cambian.
  Future<T> run<T>(T Function(Ledger l) op) async {
    final draft = _ledger.clone();
    final result = op(draft);
    await storage.save(draft);
    _ledger = draft;
    notifyListeners();
    onLocalChange?.call();
    return result;
  }

  String exportBackup() => const JsonEncoder.withIndent('  ').convert(_ledger.toJson());

  Future<void> restoreBackup(String json) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      throw FinanceException('El texto no es un respaldo válido.');
    }
    final restored = Ledger.fromJson(data);
    await storage.save(restored);
    _ledger = restored;
    notifyListeners();
    onLocalChange?.call();
  }

  /// Reemplaza los datos locales con los descargados de la nube.
  /// No cuenta como cambio local (no dispara una nueva subida).
  Future<void> replaceFromSync(Ledger remote) async {
    await storage.save(remote);
    _ledger = remote;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
