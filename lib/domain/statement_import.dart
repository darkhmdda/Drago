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
final _mon = '(${_monthAlt.join('|')})';

// --- Fechas (sobre texto normalizado: minúsculas y sin acentos) ---
// 2026-12-16
final _reIso = RegExp(r'\b(20\d{2})[/\-.](\d{1,2})[/\-.](\d{1,2})\b');
// 16/12/2026, 16-12-26, 16.12.2026
final _reNumeric = RegExp(r'\b(\d{1,2})\s?[/\-.]\s?(\d{1,2})\s?[/\-.]\s?(\d{4}|\d{2})(?!\d)');
// 16 dic, 16 de diciembre de 2026, 16/dic/2026, 16-dic-26, 16dic
final _reDayMonth = RegExp(r'\b(\d{1,2})\s*[/\-.]?\s*(?:de\s+)?' + _mon + r'\.?(?:\s*[/\-.,]?\s*(?:de(?:l)?\s+)?(\d{4}|\d{2}(?![\d:])))?(?![a-z])');
// dic 16, 2026 · diciembre 16
final _reMonthDay = RegExp(r'(?<![a-z])' + _mon + r'\.?\s*[/\-.]?\s*(\d{1,2})(?![\d:])(?:,?\s*(\d{4}))?');
// 16/12 (sin año): solo si la línea habla de pagos o trae un importe
final _reShort = RegExp(r'\b(\d{1,2})[/\-](\d{1,2})\b(?!\s*[/\-]\s*\d)');
final _reRelative = RegExp(r'\b(hoy|pasado manana|manana)\b');
final _rePayWords = RegExp(r'(vence|vencimiento|limite|pagar antes|fecha de pago|proximo pago|cuota|pago|mensualidad|quincena|parcialidad|abono)');
final _rePurchase = RegExp(r'(compra|comprado|realizad[oa]|adquirid|fecha de compra|desde el)');

// «2 de 6», «cuota 3 de 12», «pago 4/6», «3/6 mensualidades».
final _reCuota = RegExp(r'\b(?:cuota|pago|mensualidad|parcialidad|quincena)?\s*(\d{1,2})\s*(?:de|/)\s*(\d{1,2})\b(?!\s*[/\-.]\s*\d)');

// Líneas de cuotas ya pagadas (no se proponen) y de totales.
final _rePaid = RegExp(r'\b(pagad[oa]s?|pagaste|liquidad[oa]s?|cubiert[oa]s?|abonad[oa]s?|completad[oa]s?)\b');
final _reNotPaid = RegExp(r'(por pagar|a pagar|sin pagar|no pagad|pendiente de pago)');
final _reTotal = RegExp(r'(saldo|total|pendiente|deuda|por pagar|restante|adeudo|te faltan|faltan|resta )');
final _reNotTotal = RegExp(r'(cuota|pago \d|parcialidad|mensualidad|quincena|vence|fecha|\d+\s*de\s*\d+)');
// Separadores entre deudas: «Imagen 2», «Compra 3», «---».
final _reBoundary = RegExp(r'^(imagen|captura|foto|screenshot|compra|pedido|producto|orden|prestamo|credito)\b|^[-=_*]{3,}');

/// Corrige confusiones típicas del lector de texto en números:
/// «2O.12» → «20.12», «l6» → «16», «S 21.12» → «$ 21.12», espacios raros, etc.
String _ocrClean(String line) {
  var s = line
      .replaceAll(RegExp(r'[   ]'), ' ')
      .replaceAll(RegExp(r'[＄﹩]'), r'$')
      .replaceAll(RegExp(r'[–—−]'), '-')
      .replaceAll('，', ',')
      .replaceAll('．', '.');
  // «S 21.12» o «S21.12» al inicio de un importe → «$».
  s = s.replaceAllMapped(RegExp(r'(^|[\s:(])S\s?(?=\d)'), (m) => '${m[1]}\$');
  // Letras confundidas con dígitos cuando están entre dígitos.
  for (var k = 0; k < 2; k++) {
    s = s.replaceAllMapped(RegExp(r'(?<=\d)[Oo](?=[\d.,]|\b)'), (_) => '0');
    s = s.replaceAllMapped(RegExp(r'(?<=[\d$])[lI|](?=\d)'), (_) => '1');
    s = s.replaceAllMapped(RegExp(r'(?<=\d)[lI|](?=[\d.,/\-]|\b)'), (_) => '1');
    s = s.replaceAllMapped(RegExp(r'(?<![A-Za-z])[lI|](?=\d)'), (_) => '1');
  }
  return s;
}

DateTime? _mk(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null; // descarta 31 de febrero, etc.
}

DateTime? _infer(int day, int month, int? year, DateTime today) {
  if (year != null) return _mk(year < 100 ? 2000 + year : year, month, day);
  var y = today.year;
  // Sin año: el más cercano (los estados de cuenta muestran fechas próximas).
  if (month < today.month - 3) y++;
  if (month > today.month + 8) y--;
  return _mk(y, month, day);
}

class _DateHit {
  final DateTime date;
  final int start, end;
  const _DateHit(this.date, this.start, this.end);
}

List<_DateHit> _dateHits(String t, DateTime today) {
  final out = <_DateHit>[];
  final taken = List<bool>.filled(t.length + 1, false);
  void add(RegExpMatch m, DateTime? d) {
    if (d == null) return;
    for (var k = m.start; k < m.end; k++) {
      if (taken[k]) return;
    }
    for (var k = m.start; k < m.end; k++) {
      taken[k] = true;
    }
    out.add(_DateHit(d, m.start, m.end));
  }

  for (final m in _reIso.allMatches(t)) {
    add(m, _mk(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
  }
  for (final m in _reNumeric.allMatches(t)) {
    final y = int.parse(m[3]!);
    add(m, _mk(y < 100 ? 2000 + y : y, int.parse(m[2]!), int.parse(m[1]!)));
  }
  for (final m in _reDayMonth.allMatches(t)) {
    final y = int.tryParse(m[3] ?? '');
    add(m, _infer(int.parse(m[1]!), _monthNames[m[2]]!, y, today));
  }
  for (final m in _reMonthDay.allMatches(t)) {
    add(m, _infer(int.parse(m[2]!), _monthNames[m[1]]!, int.tryParse(m[3] ?? ''), today));
  }
  if (out.isEmpty && (_rePayWords.hasMatch(t) || _moneyIn(t).isNotEmpty)) {
    for (final m in _reShort.allMatches(t)) {
      // «2/6» suele ser número de cuota, no fecha.
      final a = int.parse(m[1]!), b = int.parse(m[2]!);
      if (a <= b && RegExp(r'(cuota|mensualidad|pago|parcialidad)\s*$').hasMatch(t.substring(0, m.start))) continue;
      if (a <= b && b <= 24 && !RegExp(r'\d\s*[/\-]\s*\d').hasMatch(t.substring(m.end).trimLeft().padRight(3).substring(0, 3))) {
        // Ambiguo (podría ser «cuota 2/6»): solo se acepta si parece fecha (día > 12 o con palabra de vencimiento).
        if (a <= 12 && !RegExp(r'(vence|limite|fecha)').hasMatch(t)) continue;
      }
      add(m, _infer(a, b, null, today));
    }
  }
  if (out.isEmpty && RegExp(r'(vence|limite|pag)').hasMatch(t)) {
    final m = _reRelative.firstMatch(t);
    if (m != null) {
      final d = switch (m[1]) { 'hoy' => 0, 'manana' => 1, _ => 2 };
      out.add(_DateHit(today.add(Duration(days: d)), m.start, m.end));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// La fecha de pago de una línea: si hay varias, la que sigue a «vence»,
/// «límite», «pago»…; se descarta la de compra.
DateTime? _payDate(String t, List<_DateHit> hits) {
  if (hits.isEmpty) return null;
  if (hits.length == 1) {
    final before = t.substring(0, hits.first.start);
    if (_rePurchase.hasMatch(before) && !_rePayWords.hasMatch(before)) return null;
    return hits.first.date;
  }
  for (final h in hits) {
    final before = t.substring(h.start >= 25 ? h.start - 25 : 0, h.start);
    if (RegExp(r'(vence|vencimiento|limite|pagar antes|fecha de pago|proximo pago|pago)').hasMatch(before)) return h.date;
  }
  return hits.last.date;
}

// --- Importes ---
// Con moneda: «$21.12», «$ 1,234.56», «$1 234.56», «$21,12», «$301 41» (centavos pequeños), «MXN 21.12», «$21».
final _reMoneyCur = RegExp(
    r'(?:\$|mxn|mn)\s*(\d{1,3}(?:[ ,]\d{3})+|\d+)(?:([.,])(\d{2})(?!\d)|\s(\d{2})(?![\d.,/]))?');
// Moneda al final: «21.12 MXN», «1,250.50 pesos», «400 pesos».
final _reMoneyAfter = RegExp(r'(?<![\d.,])(\d{1,3}(?:,\d{3})+|\d+)(?:([.,])(\d{2}))?\s*(?:mxn|pesos|mn)\b');
// Sin moneda, con centavos: «21.12», «1,234.56», «21,12».
final _reMoneyBare = RegExp(r'(?<![\d.,/:\-])(\d{1,3}(?:,\d{3})+|\d+)([.,])(\d{2})(?![\d.,/%:])');

List<Cents> _moneyIn(String t) {
  final out = <(int, Cents)>[];
  final taken = <int>{};
  void add(RegExpMatch m, String whole, String? cents) {
    if (taken.contains(m.start)) return;
    for (var k = m.start; k < m.end; k++) {
      taken.add(k);
    }
    final w = int.tryParse(whole.replaceAll(RegExp(r'[ ,]'), ''));
    if (w == null) return;
    out.add((m.start, w * 100 + int.parse((cents ?? '00').padRight(2, '0'))));
  }

  for (final m in _reMoneyCur.allMatches(t)) {
    add(m, m[1]!, m[3] ?? m[4]);
  }
  for (final m in _reMoneyAfter.allMatches(t)) {
    if (!taken.contains(m.start)) add(m, m[1]!, m[3]);
  }
  for (final m in _reMoneyBare.allMatches(t)) {
    if (taken.contains(m.start)) continue;
    // «1,234» con 3 dígitos tras la coma son miles, no centavos (ya excluido por la regex).
    add(m, m[1]!, m[3]);
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final e in out) e.$2];
}

/// Importes de una línea sin contar lo que ya se leyó como fecha.
List<Cents> _money(String t, List<_DateHit> hits) {
  var s = t;
  for (final h in hits.reversed) {
    s = s.replaceRange(h.start, h.end, ' ' * (h.end - h.start));
  }
  // Tampoco «2 de 6» ni porcentajes.
  s = s.replaceAll(_reCuota, ' ').replaceAll(RegExp(r'\d+(?:[.,]\d+)?\s*%'), ' ');
  return _moneyIn(s);
}

(int?, int?) _cuotaIn(String t, List<_DateHit> hits) {
  var s = t;
  for (final h in hits.reversed) {
    s = s.replaceRange(h.start, h.end, ' ' * (h.end - h.start));
  }
  for (final m in _reCuota.allMatches(s)) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!);
    // «2 de 6» es cuota; «16 de 2026» no.
    if (a >= 1 && a <= b && b >= 2 && b <= 60) return (a, b);
  }
  return (null, null);
}

class _Line {
  final String raw;
  final String t;
  final List<_DateHit> hits;
  final DateTime? date;
  final List<Cents> money;
  final bool total, paid, boundary;
  final int? number, of;
  _Line(this.raw, this.t, this.hits, this.date, this.money, this.total, this.paid, this.boundary, this.number, this.of);
}

/// Interpreta el texto leído de una captura (OCR) o pegado a mano.
///
/// Tolera las variaciones habituales: fechas en cualquier formato común,
/// importes con o sin «$», coma decimal, centavos pequeños, errores típicos
/// del lector de texto, fecha e importe en la misma línea, en líneas vecinas o
/// en columnas separadas. Ignora cuotas marcadas como pagadas y separa varias
/// deudas en bloques.
ParsedStatement parseStatement(String text, {required DateTime today, List<String> extraNames = const []}) {
  final rawLines = text.split(RegExp(r'\r?\n'));
  final lines = <_Line>[];
  final boundaryBefore = <int>{}; // índices de líneas precedidas por un separador
  var blanks = 0;
  for (final rl in rawLines) {
    final raw = rl.trim();
    if (raw.isEmpty) {
      blanks++;
      continue;
    }
    final t = normalize(_ocrClean(raw));
    final hits = _dateHits(t, today);
    final total = _reTotal.hasMatch(t) && !_reNotTotal.hasMatch(t);
    final paid = _rePaid.hasMatch(t) && !_reNotPaid.hasMatch(t);
    final boundary = _reBoundary.hasMatch(t) && hits.isEmpty;
    final (number, of) = _cuotaIn(t, hits);
    if (blanks >= 2 || boundary) boundaryBefore.add(lines.length);
    blanks = 0;
    lines.add(_Line(raw, t, hits, _payDate(t, hits), _money(t, hits), total, paid, boundary, number, of));
  }
  final all = normalize(text);

  String? institution;
  for (final name in [...extraNames, ...knownInstitutions]) {
    final n = normalize(name);
    if (n.length >= 2 && RegExp('(^|[^a-z])${RegExp.escape(n)}([^a-z]|\$)').hasMatch(all)) {
      institution = name;
      break;
    }
  }

  // Total pendiente.
  Cents? total;
  final usedMoney = <int>{};
  for (var i = 0; i < lines.length && total == null; i++) {
    if (!lines[i].total) continue;
    if (lines[i].money.isNotEmpty) {
      total = lines[i].money.first;
      usedMoney.add(i);
    } else if (i + 1 < lines.length && lines[i + 1].money.isNotEmpty && lines[i + 1].date == null) {
      total = lines[i + 1].money.first;
      usedMoney.add(i + 1);
    }
  }

  // Número de cuota: de la línea o de una línea vecina sin fecha («Cuota 2 de 6» arriba).
  (int?, int?) cuotaNear(int i, int j) {
    for (final k in [i, j, i - 1]) {
      if (k >= 0 && k < lines.length && lines[k].number != null && (k == i || k == j || lines[k].date == null)) {
        return (lines[k].number, lines[k].of);
      }
    }
    return (null, null);
  }

  // Paso A: fecha con importe en la misma línea o en una vecina.
  final a = <(int, DetectedPayment)>[];
  final usedA = {...usedMoney};
  final paidLines = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.total || l.date == null) continue;
    var src = -1;
    if (l.money.isNotEmpty && !usedA.contains(i)) {
      src = i;
    } else {
      for (final j in [i + 1, i - 1, i + 2]) {
        if (j < 0 || j >= lines.length || usedA.contains(j) || lines[j].date != null || lines[j].total || lines[j].money.isEmpty) continue;
        src = j;
        break;
      }
    }
    if (src < 0) continue;
    usedA.add(src);
    if (l.paid || lines[src].paid) {
      paidLines.add(i);
      continue;
    }
    final (n, of) = cuotaNear(i, src);
    a.add((i < src ? i : src, DetectedPayment(l.date!, lines[src].money.first, i == src ? l.raw : '${l.raw} · ${lines[src].raw}', number: n, of: of)));
  }

  // Paso B: columnas (todas las fechas y luego todos los importes, o al revés).
  final dateIdx = [for (var i = 0; i < lines.length; i++) if (lines[i].date != null && !lines[i].total && !lines[i].paid && lines[i].money.isEmpty) i];
  final moneyIdx = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].date == null && lines[i].money.isNotEmpty && !lines[i].total && !lines[i].paid && !usedMoney.contains(i)) i
  ];
  final b = <(int, DetectedPayment)>[];
  if (dateIdx.length >= 2 && dateIdx.length == moneyIdx.length) {
    for (var k = 0; k < dateIdx.length; k++) {
      final i = dateIdx[k], j = moneyIdx[k];
      final (n, of) = cuotaNear(i, j);
      b.add((i < j ? i : j, DetectedPayment(lines[i].date!, lines[j].money.first, '${lines[i].raw} · ${lines[j].raw}', number: n, of: of)));
    }
  }
  // También cuentan las líneas que ya traían fecha e importe juntos.
  final sameLine = [for (final e in a) if (lines[e.$1].date != null && lines[e.$1].money.isNotEmpty) e];
  final candidateB = [...sameLine, ...b]..sort((x, y) => x.$1.compareTo(y.$1));
  final chosen = candidateB.length > a.length ? candidateB : a;

  // Bloques: separador explícito, o numeración que vuelve a empezar / cambia el total.
  final groups = <List<DetectedPayment>>[];
  (int, DetectedPayment)? prev;
  for (final e in chosen) {
    final p = e.$2;
    final sep = prev != null && boundaryBefore.any((k) => k > prev!.$1 && k <= e.$1);
    final restart = prev != null &&
        p.number != null &&
        prev.$2.number != null &&
        (p.number! <= prev.$2.number! || (p.of != null && prev.$2.of != null && p.of != prev.$2.of));
    if (groups.isEmpty || restart || sep) groups.add([]);
    groups.last.add(p);
    prev = e;
  }
  // En cada bloque: sin duplicados (misma fecha e importe) y en orden.
  final clean = [
    for (final g in groups)
      () {
        final seen = <String>{};
        return [
          for (final p in g..sort((x, y) => x.date.compareTo(y.date)))
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
