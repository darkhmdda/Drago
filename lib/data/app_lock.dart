import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LockMethod { device, pin }

/// Bloqueo de la app al abrirla y al volver tras un rato en segundo plano.
/// - Android: bloqueo del teléfono (huella, rostro, PIN o patrón).
/// - Web (o teléfono sin bloqueo): PIN de Drago, guardado solo como hash.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  static const _kEnabled = 'drago.lock.enabled';
  static const _kMethod = 'drago.lock.method';
  static const _kSalt = 'drago.lock.salt';
  static const _kHash = 'drago.lock.hash';

  /// Tiempo en segundo plano tras el cual se vuelve a pedir desbloqueo.
  static const relockAfter = Duration(seconds: 60);

  final _auth = LocalAuthentication();
  bool enabled = false;
  LockMethod method = LockMethod.pin;
  bool locked = false;
  String? _salt;
  String? _hash;
  DateTime? _pausedAt;

  bool get deviceAuthPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? false;
    method = LockMethod.values.firstWhere((m) => m.name == p.getString(_kMethod), orElse: () => LockMethod.pin);
    _salt = p.getString(_kSalt);
    _hash = p.getString(_kHash);
    if (enabled && method == LockMethod.pin && _hash == null) enabled = false; // configuración incompleta
    locked = enabled;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _pausedAt;
      _pausedAt = null;
      if (since != null && DateTime.now().difference(since) >= relockAfter && !locked) {
        locked = true;
        notifyListeners();
      }
    }
  }

  /// ¿El teléfono tiene huella/rostro/PIN configurado?
  Future<bool> deviceAuthAvailable() async {
    if (!deviceAuthPlatform) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deviceAuth(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }

  String _digest(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setString(_kMethod, method.name);
    if (_salt != null) await p.setString(_kSalt, _salt!);
    if (_hash != null) {
      await p.setString(_kHash, _hash!);
    } else {
      await p.remove(_kHash);
    }
  }

  /// Activa el bloqueo con el del teléfono (pide verificar primero).
  Future<bool> enableDevice() async {
    if (!await _deviceAuth('Confirma que eres tú para activar el bloqueo de Drago')) return false;
    enabled = true;
    method = LockMethod.device;
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> enablePin(String pin) async {
    final r = Random.secure();
    _salt = base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
    _hash = _digest(pin, _salt!);
    enabled = true;
    method = LockMethod.pin;
    await _save();
    notifyListeners();
  }

  Future<void> disable() async {
    enabled = false;
    locked = false;
    _hash = null;
    await _save();
    notifyListeners();
  }

  Future<bool> unlockWithDevice() async {
    final ok = await _deviceAuth('Desbloquea Drago');
    if (ok) {
      locked = false;
      notifyListeners();
    }
    return ok;
  }

  bool checkPin(String pin) => _hash != null && _salt != null && _digest(pin, _salt!) == _hash;

  bool unlockWithPin(String pin) {
    if (!checkPin(pin)) return false;
    locked = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
