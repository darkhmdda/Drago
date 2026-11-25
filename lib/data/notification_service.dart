import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';
import 'app_state.dart';

/// Recordatorios de pagos.
///
/// - Android: notificaciones del sistema programadas (funcionan con la app
///   cerrada). Se reprograman cada vez que cambian los datos, así un pago
///   realizado deja de avisar y una fecha cambiada avisa en la nueva fecha.
/// - Web: los navegadores no permiten programar notificaciones; se usa el
///   centro de notificaciones dentro de la app.
class NotificationService extends ChangeNotifier {
  final AppState app;
  NotificationService(this.app);

  static const _kSettings = 'drago.reminders';
  static const _kSeen = 'drago.reminders.seen';
  static const _channelId = 'pagos';

  final _plugin = FlutterLocalNotificationsPlugin();
  ReminderSettings settings = const ReminderSettings();
  Set<String> _seen = {};
  bool _systemReady = false;
  bool? permissionGranted;

  /// Motivo por el que no se pudo iniciar el sistema de notificaciones.
  String? initError;
  Timer? _debounce;
  AppLifecycleListener? _lifecycle;

  /// true si este dispositivo puede mostrar notificaciones del sistema.
  bool get supportsSystemNotifications => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSettings);
    if (raw != null) {
      try {
        settings = ReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    _seen = (p.getStringList(_kSeen) ?? const []).toSet();

    if (supportsSystemNotifications) await _initSystem();
    app.addListener(_scheduleSoon);
    if (supportsSystemNotifications) _lifecycle = AppLifecycleListener(onResume: refreshPermission);
    await reschedule();
  }

  Future<void> _initSystem() async {
    try {
      tzdata.initializeTimeZones();
      try {
        await _plugin.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_drago')),
        );
      } catch (_) {
        // Respaldo: el icono de la app siempre existe.
        await _plugin.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        );
      }
      _systemReady = true;
      initError = null;
      permissionGranted = await _android?.areNotificationsEnabled();
    } catch (e) {
      initError = '$e';
      debugPrint('Notificaciones no disponibles: $e');
    }
  }

  /// Vuelve a consultar si el permiso está activo (por ejemplo, al regresar
  /// de los ajustes del teléfono).
  Future<void> refreshPermission() async {
    if (!supportsSystemNotifications) return;
    if (!_systemReady) await _initSystem();
    if (_systemReady) permissionGranted = await _android?.areNotificationsEnabled();
    notifyListeners();
    if (permissionGranted == true) await reschedule();
  }

  /// Abre la pantalla de notificaciones de Drago en los ajustes del teléfono.
  Future<void> openSystemSettings() async {
    try {
      await _android?.openAppNotificationSettings();
    } catch (_) {}
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Pide permiso (Android 13+). Debe llamarse tras una acción del usuario.
  Future<bool> requestPermission() async {
    if (!_systemReady) await _initSystem();
    if (!_systemReady) {
      notifyListeners();
      return false;
    }
    try {
      permissionGranted = await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      // Si ya había una solicitud en curso, se consulta el estado actual.
      permissionGranted = await _android?.areNotificationsEnabled() ?? false;
    }
    if (permissionGranted != true) permissionGranted = await _android?.areNotificationsEnabled() ?? false;
    notifyListeners();
    if (permissionGranted == true) await reschedule();
    return permissionGranted!;
  }

  Future<void> updateSettings(ReminderSettings s) async {
    settings = s;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSettings, jsonEncode(s.toJson()));
    notifyListeners();
    await reschedule();
  }

  void _scheduleSoon() {
    notifyListeners(); // el centro de notificaciones depende de los datos
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), reschedule);
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Recordatorios de pagos',
      channelDescription: 'Avisos antes de que venzan tus pagos y cuando esperas un ingreso.',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      icon: '@drawable/ic_stat_drago',
      color: Color(0xFF8A5A00),
    ),
  );

  /// Cancela todo y vuelve a programar los próximos recordatorios.
  Future<void> reschedule() async {
    if (!_systemReady) return;
    try {
      await _plugin.cancelAll();
      if (!settings.enabled) return;
      final now = DateTime.now();
      for (final r in upcomingReminders(app.ledger, settings, now)) {
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: tz.TZDateTime.from(r.fireAt.toUtc(), tz.UTC),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Recordatorios de pagos',
              channelDescription: 'Avisos antes de que venzan tus pagos y cuando esperas un ingreso.',
              importance: Importance.high,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(r.body),
              icon: '@drawable/ic_stat_drago',
              color: const Color(0xFF8A5A00),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
        );
      }
    } catch (e) {
      debugPrint('No se pudieron programar los recordatorios: $e');
    }
  }

  /// Muestra una notificación de prueba ahora mismo.
  Future<void> showTest() async {
    if (!_systemReady) await _initSystem();
    if (!_systemReady) return;
    await _plugin.show(
      id: 1,
      title: 'Drago: notificaciones activas',
      body: 'Así te avisaremos antes de cada pago.',
      notificationDetails: _details,
    );
  }

  // ------------------------------------------------------------------
  // Centro de notificaciones dentro de la app
  // ------------------------------------------------------------------

  List<Reminder> get inbox => dueReminders(app.ledger, settings, DateTime.now());

  int get unseenCount => inbox.where((r) => !_seen.contains(r.key)).length;

  bool isSeen(Reminder r) => _seen.contains(r.key);

  Future<void> markAllSeen() async {
    final keys = inbox.map((r) => r.key).toSet();
    // Solo se guardan las claves vigentes, para que la lista no crezca sin fin.
    _seen = keys;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kSeen, _seen.toList());
    notifyListeners();
  }

  @override
  void dispose() {
    app.removeListener(_scheduleSoon);
    _debounce?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
