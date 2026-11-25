import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/money.dart';
import '../domain/report.dart';

/// Las fuentes estándar del PDF (Helvetica) cubren el español (acentos, ñ, ¿¡),
/// pero no algunos símbolos: se sustituyen por equivalentes simples.
String _safe(String s) => s.replaceAll('→', '->').replaceAll('…', '...').replaceAll('✓', 'OK');

String _cell(Object? v) => switch (v) {
      null => '',
      Amount a => formatMoney(a.cents),
      Day d => '${d.date.day.toString().padLeft(2, '0')}/${d.date.month.toString().padLeft(2, '0')}/${d.date.year}',
      _ => _safe(v.toString()),
    };

/// Genera el reporte en PDF (tamaño carta, una sección por tabla).
Future<Uint8List> buildPdf(List<ReportTable> tables, {required String title, required String subtitle}) async {
  const brand = PdfColor.fromInt(0xFF1F6F5C);
  final doc = pw.Document(title: title, author: 'Drago');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter.copyWith(marginLeft: 36, marginRight: 36, marginTop: 40, marginBottom: 40),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: brand, width: 1.5))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Drago', style: pw.TextStyle(color: brand, fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Text(_safe(subtitle), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ]),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (ctx) => [
        pw.SizedBox(height: 8),
        pw.Text(_safe(title), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('Los saldos y movimientos son reales; lo previsto aparece marcado como «Previsto».',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        for (final t in tables) ...[
          pw.SizedBox(height: 14),
          pw.Text(_safe(t.name), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: brand)),
          pw.SizedBox(height: 4),
          if (t.rows.isEmpty)
            pw.Text('Sin registros en el periodo.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))
          else
            pw.TableHelper.fromTextArray(
              headers: t.headers.map(_safe).toList(),
              data: [for (final r in t.rows) r.map(_cell).toList()],
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: brand),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F6F4)),
              columnWidths: {
                for (var c = 0; c < t.headers.length; c++)
                  c: t.rows.any((r) => c < r.length && r[c] is Day)
                      ? const pw.FixedColumnWidth(54)
                      : t.rows.any((r) => c < r.length && r[c] is Amount)
                          ? const pw.FixedColumnWidth(64)
                          : const pw.FlexColumnWidth(),
              },
              cellAlignments: {
                for (var c = 0; c < t.headers.length; c++)
                  if (t.rows.any((r) => c < r.length && r[c] is Amount)) c: pw.Alignment.centerRight,
              },
            ),
        ],
      ],
    ),
  );
  return doc.save();
}

const pdfMime = 'application/pdf';
