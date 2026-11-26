import 'assistant.dart' show normalize;
import 'ledger.dart';
import 'models.dart';
import 'money.dart';

/// Un pago detectado en una captura (fecha + importe).
class DetectedPayment {
  final DateTime date;
  final Cents amount;
  final String line;

  /// Número de cuota si la captura lo indica («2 de 6» → 2).
  final int? number;

  /// Total de cuotas si la captura lo indica («2 de 6» → 6).
  final int? of;
  const DetectedPayment(this.date, this.amount, this.line, {this.number, this.of});
}

/// Lo que se pudo leer de una captura de estado de cuenta.
class ParsedStatement {
  final String? institution;

  /// Bloques de pagos. Si el texto trae varias deudas (por ejemplo, varias
  /// capturas pegadas juntas), cada una queda en su propio bloque: se detecta
  /// cuando la numeración de cuotas vuelve a empezar («6 de 6» → «3 de 6»).
  final List<List<DetectedPayment>> groups;

  /// Saldo o total pendiente que menciona la captura, si lo hay.
  final Cents? totalPending;
  const ParsedStatement({this.institution, this.groups = const [], this.totalPending});

  /// Todos los pagos detectados (de todos los bloques).
  List<DetectedPayment> get payments => [for (final g in groups) ...g];
  bool get isEmpty => groups.every((g) => g.isEmpty) && totalPending == null;

  /// Solo un bloque (el total pendiente aplica únicamente si hay un solo bloque).
  ParsedStatement forGroup(int i) =>
      ParsedStatement(institution: institution, groups: [groups[i]], totalPending: groups.length == 1 ? totalPending : null);
}

const _monthNames = {
  'ene': 1, 'enero': 1, 'feb': 2, 'febrero': 2, 'mar': 3, 'marzo': 3, 'abr': 4, 'abril': 4, 'may': 5, 'mayo': 5,
  'jun': 6, 'junio': 6, 'jul': 7, 'julio': 7, 'ago': 8, 'agosto': 8, 'sep': 9, 'sept': 9, 'septiembre': 9,
  'setiembre': 9, 'oct': 10, 'octubre': 10, 'nov': 11, 'noviembre': 11, 'dic': 12, 'diciembre': 12,
};

const knownInstitutions = ['DiDi', 'Mercado Pago', 'Coppel', 'Nu', 'BBVA', 'Banamex', 'Santander', 'Banorte', 'Klar', 'Stori',
  'Kueski', 'Elektra', 'Liverpool', 'Aplazo', 'Baubap', 'Plata', 'Spin', 'HSBC', 'Banco Azteca'];

final _monthAlt = _monthNames.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
// «16 dic», «16 de diciembre de 2026», «16/dic/2026», «16-dic-26».
final _reDayMonth = RegExp(r'\b(\d{1,2})\s*[/\-.]?\s*(?:de\s+)?(' +
    _monthAlt.join('|') +
    r')\.?(?:\s*[/\-.]?\s*(?:de(?:l)?\s+)?(\d{4}|\d{2}(?!\d)))?(?![a-z])');
// «2 de 6», «cuota 3 de 12», «pago 4/6».
final _reCuota = RegExp(r'\b(?:cuota|pago|mensualidad|parcialidad)?\s*(\d{1,2})\s*(?:de|/)\s*(\d{1,2})\b(?!\s*[/\-.]\s*\d)');
final _reMonthDay = RegExp(r'\b(' + _monthAlt.join('|') + r')\.?\s+(\d{1,2})(?:,?\s*(\d{4}))?\b');
final _reNumeric = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b');
// Importes con centavos o con signo de pesos (para no confundir días o folios con dinero).
final _reMoney = RegExp(r'(?:\$|mxn)\s*(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{2}))?|\b(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})\b');

DateTime _infer(int day, int month, int? year, DateTime today) {
  if (year != null) return DateTime(year < 100 ? 2000 + year : year, month, day);
  var y = today.year;
  // Sin año: el más cercano (los estados de cuenta muestran fechas próximas).
  if (month < today.month - 3) y++;
  if (month > today.month + 8) y--;
  return DateTime(y, month, day);
}

List<DateTime> _dates(String t, DateTime today) {
  final out = <DateTime>[];
  for (final m in _reDayMonth.allMatches(t)) {
    final d = int.parse(m.group(1)!);
    final y = int.tryParse(m.group(3) ?? '');
    if (d >= 1 && d <= 31) out.add(_infer(d, _monthNames[m.group(2)]!, y == null ? null : (y < 100 ? 2000 + y : y), today));
  }
  if (out.isEmpty) {
    for (final m in _reMonthDay.allMatches(t)) {
      final d = int.parse(m.group(2)!);
      if (d >= 1 && d <= 31) out.add(_infer(d, _monthNames[m.group(1)]!, int.tryParse(m.group(3) ?? ''), today));
    }
  }
  if (out.isEmpty) {
    for (final m in _reNumeric.allMatches(t)) {
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
      if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) out.add(_infer(d, mo, int.parse(m.group(3)!), today));
    }
  }
  return out;
}

List<Cents> _money(String t) {
  final out = <Cents>[];
  for (final m in _reMoney.allMatches(t)) {
    final whole = (m.group(1) ?? m.group(3))!.replaceAll(',', '');
    final frac = m.group(2) ?? m.group(4) ?? '00';
    out.add(int.parse(whole) * 100 + int.parse(frac.padRight(2, '0')));
  }
  return out;
}

bool _isTotalLine(String t) =>
    RegExp(r'(saldo|total|pendiente|deuda|por pagar|restante|adeudo)').hasMatch(t) &&
    !RegExp(r'(cuota|pago \d|parcialidad|mensualidad|quincena|vence|fecha)').hasMatch(t);

/// Interpreta el texto leído de una captura (OCR).
///
/// Busca fechas con importe en la misma línea o en líneas vecinas (las apps
/// suelen poner la fecha arriba o abajo del importe) y el total pendiente.
ParsedStatement parseStatement(String text, {required DateTime today, List<String> extraNames = const []}) {
  final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final norm = lines.map(normalize).toList();
  final all = normalize(text);

  String? institution;
  for (final name in [...extraNames, ...knownInstitutions]) {
    final n = normalize(name);
    if (n.length >= 2 && RegExp('(^|[^a-z])${RegExp.escape(n)}([^a-z]|\$)').hasMatch(all)) {
      institution = name;
      break;
    }
  }

  Cents? total;
  final payments = <DetectedPayment>[];
  final usedMoney = <int>{};
  for (var i = 0; i < norm.length; i++) {
    final t = norm[i];
    if (_isTotalLine(t)) {
      final m = _money(t).isNotEmpty ? _money(t) : (i + 1 < norm.length ? _money(norm[i + 1]) : const <Cents>[]);
      if (m.isNotEmpty && total == null) {
        total = m.first;
        usedMoney.add(_money(t).isNotEmpty ? i : i + 1);
      }
      continue;
    }
    final ds = _dates(t, today);
    if (ds.isEmpty) continue;
    var ms = _money(t);
    var src = i;
    if (ms.isEmpty) {
      // Importe en la línea siguiente o en la anterior.
      for (final j in [i + 1, i - 1, i + 2]) {
        if (j < 0 || j >= norm.length || usedMoney.contains(j) || _dates(norm[j], today).isNotEmpty) continue;
        final mj = _money(norm[j]);
        if (mj.isNotEmpty) {
          ms = mj;
          src = j;
          break;
        }
      }
    }
    if (ms.isEmpty) continue;
    usedMoney.add(src);
    final cuota = _reCuota.firstMatch(t.replaceAll(RegExp(r'\d{1,2}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{2,4}'), ' '));
    int? number, of;
    if (cuota != null) {
      final a = int.parse(cuota.group(1)!), b = int.parse(cuota.group(2)!);
      if (a >= 1 && a <= b && b <= 60) {
        number = a;
        of = b;
      }
    }
    payments.add(DetectedPayment(ds.first, ms.first, lines[i] == lines[src] ? lines[i] : '${lines[i]} · ${lines[src]}',
        number: number, of: of));
  }

  // Bloques: uno nuevo cada vez que la numeración de cuotas vuelve a empezar
  // o cambia el total de cuotas (otra deuda).
  final groups = <List<DetectedPayment>>[];
  DetectedPayment? prev;
  for (final p in payments) {
    final restart = prev != null &&
        p.number != null &&
        prev.number != null &&
        (p.number! <= prev.number! || (p.of != null && prev.of != null && p.of != prev.of));
    if (groups.isEmpty || restart) groups.add([]);
    groups.last.add(p);
    prev = p;
  }
  // En cada bloque: sin duplicados (misma fecha e importe) y en orden.
  final clean = [
    for (final g in groups)
      () {
        final seen = <String>{};
        return [
          for (final p in g..sort((a, b) => a.date.compareTo(b.date)))
            if (seen.add('${p.date}|${p.amount}')) p,
        ];
      }(),
  ];
  return ParsedStatement(institution: institution, groups: clean, totalPending: total);
}

// ---------------------------------------------------------------------------
// Comparación con los registros
// ---------------------------------------------------------------------------

enum ChangeKind { update, newInstallment, unchanged, alreadyPaid }

class ProposedChange {
  final ChangeKind kind;
  final DetectedPayment detected;
  final Installment? installment;
  const ProposedChange(this.kind, this.detected, [this.installment]);

  Cents? get before => installment?.amount;
}

/// Encuentra la deuda que corresponde a la institución detectada.
Debt? matchDebt(Ledger l, ParsedStatement s) {
  if (s.institution == null) return null;
  final inst = normalize(s.institution!);
  for (final d in l.debts.where((d) => d.status == DebtStatus.active)) {
    final n = normalize(d.name);
    if (n.contains(inst) || inst.contains(n.split(' ').first)) return d;
  }
  return null;
}

/// Compara lo detectado con las cuotas abiertas de [debt]:
/// - fecha cercana (±3 días) con importe o fecha distintos → actualizar;
/// - igual → sin cambios;
/// - sin cuota cercana → nueva cuota.
/// Nunca propone borrar cuotas.
List<ProposedChange> compareWithDebt(Ledger l, Debt debt, ParsedStatement s) {
  final open = l.installmentsOf(debt.id).where(l.isInstallmentOpen).toList();
  final used = <String>{};
  final out = <ProposedChange>[];
  for (final p in s.payments) {
    Installment? best;
    var bestGap = 4;
    for (final i in open) {
      if (used.contains(i.id)) continue;
      final gap = i.dueDate.difference(p.date).inDays.abs();
      if (gap < bestGap) {
        best = i;
        bestGap = gap;
      }
    }
    // Sin fecha cercana: si la captura dice el número de cuota, se usa ese.
    if (best == null && p.number != null) {
      best = open.where((i) => i.number == p.number && !used.contains(i.id)).firstOrNull;
    }
    if (best == null) {
      // ¿Corresponde a una cuota ya pagada? Entonces no se propone nada.
      final paid = l.installmentsOf(debt.id).where((i) =>
          !l.isInstallmentOpen(i) && !i.cancelled && i.dueDate.difference(p.date).inDays.abs() <= 3);
      out.add(paid.isNotEmpty
          ? ProposedChange(ChangeKind.alreadyPaid, p, paid.first)
          : ProposedChange(ChangeKind.newInstallment, p));
    } else {
      used.add(best.id);
      out.add(ProposedChange(best.amount == p.amount && best.dueDate == p.date ? ChangeKind.unchanged : ChangeKind.update, p, best));
    }
  }
  return out;
}

/// Aplica los cambios elegidos (todo o nada, dentro de AppState.run).
void applyChanges(Ledger l, Debt debt, List<ProposedChange> changes) {
  for (final c in changes) {
    switch (c.kind) {
      case ChangeKind.update:
        l.updateInstallment(c.installment!.id, amount: c.detected.amount, dueDate: c.detected.date);
      case ChangeKind.newInstallment:
        l.addInstallment(debt.id, amount: c.detected.amount, dueDate: c.detected.date);
      case ChangeKind.unchanged:
      case ChangeKind.alreadyPaid:
        break;
    }
  }
}

/// Sugiere la deuda que mejor coincide con un bloque de pagos: la que tiene
/// más cuotas con fecha cercana (±3 días) o mismo número, y mismo importe.
Debt? suggestDebt(Ledger l, List<DetectedPayment> block) {
  Debt? best;
  var bestScore = 0;
  for (final d in l.debts.where((d) => d.status == DebtStatus.active)) {
    final insts = l.installmentsOf(d.id);
    var score = 0;
    for (final p in block) {
      final hit = insts.any((i) =>
          (i.dueDate.difference(p.date).inDays.abs() <= 3 || (p.number != null && i.number == p.number)) &&
          i.amount == p.amount);
      final near = insts.any((i) => i.dueDate.difference(p.date).inDays.abs() <= 3);
      score += hit ? 3 : (near ? 1 : 0);
    }
    if (score > bestScore) {
      best = d;
      bestScore = score;
    }
  }
  return best;
}
