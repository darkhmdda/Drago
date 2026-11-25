// Compara dos respaldos JSON ignorando el formato de las marcas de tiempo.
// Uso: dart run tool/compare_ledgers.dart a.json b.json
import 'dart:convert';
import 'dart:io';

import 'package:drago/domain/ledger.dart';

Object? _strip(Object? v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (!const {'createdAt', 'at', 'syncVersion', 'schemaVersion'}.contains(e.key)) e.key: _strip(e.value)
    };
  }
  if (v is List) {
    final list = v.map(_strip).toList();
    list.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    return list;
  }
  return v;
}

void main(List<String> args) {
  final a = Ledger.fromJson(jsonDecode(File(args[0]).readAsStringSync()));
  final b = Ledger.fromJson(jsonDecode(File(args[1]).readAsStringSync()));
  final ja = jsonEncode(_strip(a.toJson()));
  final jb = jsonEncode(_strip(b.toJson()));
  stdout.writeln(ja == jb ? 'IGUALES' : 'DIFERENTES');
  stdout.writeln('total disponible: ${a.totalAvailable} vs ${b.totalAvailable}');
  stdout.writeln('movimientos: ${a.transactions.length} vs ${b.transactions.length}; previstos: ${a.scheduledItems.length} vs ${b.scheduledItems.length}');
  if (ja != jb) {
    for (var i = 0; i < ja.length && i < jb.length; i++) {
      if (ja[i] != jb[i]) {
        stdout.writeln('A: ${ja.substring(i - 80 < 0 ? 0 : i - 80, i + 80 > ja.length ? ja.length : i + 80)}');
        stdout.writeln('B: ${jb.substring(i - 80 < 0 ? 0 : i - 80, i + 80 > jb.length ? jb.length : i + 80)}');
        break;
      }
    }
    exitCode = 1;
  }
}
