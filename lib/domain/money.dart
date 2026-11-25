import 'package:intl/intl.dart';

/// Las cantidades monetarias se manejan SIEMPRE como centavos enteros (int).
/// Nunca se usa punto flotante para dinero.
typedef Cents = int;

final _fmt = NumberFormat.currency(locale: 'es_MX', symbol: r'$', decimalDigits: 2);

/// Formatea centavos como moneda: 123456 -> "$1,234.56".
String formatMoney(Cents cents, {bool signed = false}) {
  final abs = cents.abs();
  final text = _fmt.format(abs ~/ 100).replaceAll(RegExp(r'\.00$'), '');
  final withCents = '$text.${(abs % 100).toString().padLeft(2, '0')}';
  if (cents < 0) return '-$withCents';
  if (signed && cents > 0) return '+$withCents';
  return withCents;
}

/// Convierte texto escrito por el usuario a centavos sin pasar por double.
/// Acepta "500", "500.5", "1,234.56", "$1,234.56". Devuelve null si no es válido.
Cents? parseMoney(String input) {
  var s = input.trim().replaceAll(r'$', '').replaceAll(',', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  }
  final m = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final cents = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  return negative ? -cents : cents;
}
