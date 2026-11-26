import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ledger.dart';
import '../domain/money.dart';
import '../ui/themes.dart';
import 'app_state.dart';

/// Widget de calendario en la pantalla de inicio (solo Android).
///
/// Drago calcula aquí los pagos e ingresos pendientes de los próximos meses y
/// se los pasa al widget junto con los colores del tema. El widget (Kotlin,
/// `DragoCalendarWidget`) dibuja el mes y la lista de próximos movimientos
/// aunque la app esté cerrada; se actualiza cada vez que cambian los datos.
class WidgetService extends ChangeNotifier {
  final AppState app;
  final ThemeController theme;
  WidgetService(this.app, this.theme);

  static const _kHide = 'drago.widget.hideAmounts';
  static const androidName = 'DragoCalendarWidget';

  /// Ocultar los importes en el widget (solo se ven nombres y puntos de color).
  bool hideAmounts = false;

  /// Enlaces que llegan al tocar el widget (los atiende la pantalla principal).
  final launches = ValueNotifier<Uri?>(null);

  Timer? _debounce;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    hideAmounts = p.getBool(_kHide) ?? false;
    if (!supported) return;
    app.addListener(_soon);
    theme.addListener(_soon);
    AppLifecycleListener(onResume: _soon);
    HomeWidget.widgetClicked.listen(_onLaunch);
    _onLaunch(await HomeWidget.initiallyLaunchedFromHomeWidget());
    await refresh();
  }

  void _onLaunch(Uri? uri) {
    if (uri == null || uri.scheme != 'drago') return;
    launches.value = uri;
  }

  Future<void> setHideAmounts(bool v) async {
    hideAmounts = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHide, v);
    await refresh();
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), refresh);
  }

  Future<void> refresh() async {
    if (!supported) return;
    try {
      final data = buildWidgetData(app.ledger, theme.theme.data, hideAmounts: hideAmounts);
      await HomeWidget.saveWidgetData<String>('calendar', jsonEncode(data));
      await HomeWidget.updateWidget(androidName: androidName);
    } catch (e) {
      debugPrint('No se pudo actualizar el widget: $e');
    }
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Datos para el widget: movimientos pendientes desde el inicio del mes
/// actual hasta 4 meses adelante, y la paleta del tema.
@visibleForTesting
Map<String, dynamic> buildWidgetData(Ledger l, ThemeData theme, {required bool hideAmounts}) {
  final today = l.today;
  final from = DateTime(today.year, today.month, 1);
  final to = DateTime(today.year, today.month + 5, 0);
  // También los vencidos de meses anteriores que siguen sin pagarse.
  final events = l
      .eventsBetween(from.subtract(const Duration(days: 120)), to)
      .where((e) => e.isOpen && (!e.date.isBefore(from) || e.overdue))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final cs = theme.colorScheme;
  final fin = theme.extension<FinPalette>();
  int c(Color x) => x.toARGB32();
  String link(CalendarEvent e) {
    if (e.installmentId != null) {
      final inst = l.installments.where((i) => i.id == e.installmentId).firstOrNull;
      if (inst != null) return 'drago://debt?id=${inst.debtId}&date=${_ymd(e.date)}';
    }
    return 'drago://calendar?date=${_ymd(e.date)}';
  }

  return {
    'v': 1,
    'hide': hideAmounts,
    'colors': {
      'bg': c(cs.surfaceContainer),
      'text': c(cs.onSurface),
      'muted': c(cs.onSurfaceVariant),
      'primary': c(cs.primary),
      'onPrimary': c(cs.onPrimary),
      'income': c(fin?.income ?? Colors.green),
      'expense': c(fin?.expense ?? Colors.red),
      'pending': c(fin?.pending ?? Colors.orange),
    },
    'events': [
      for (final e in events.take(200))
        {
          'd': _ymd(e.date),
          // «Didi Préstamos · cuota 1» → «Didi Préstamos #1» (cabe mejor).
          't': e.title.replaceAllMapped(RegExp(r' · cuota (\d+)'), (m) => ' #${m[1]}'),
          'a': formatMoney(e.signed, signed: true),
          'k': e.isIncome ? 'i' : 'e',
          if (e.overdue) 'o': 1,
          'u': link(e),
        },
    ],
  };
}

class WidgetScope extends InheritedNotifier<WidgetService> {
  const WidgetScope({super.key, required WidgetService? service, required super.child}) : super(notifier: service);
  static WidgetService? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<WidgetScope>()?.notifier;
}
