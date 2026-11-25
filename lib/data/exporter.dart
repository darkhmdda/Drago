import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/report.dart';

/// Genera el archivo .xlsx con una hoja por tabla.
Uint8List buildXlsx(List<ReportTable> tables) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final header = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#D9EAD3'));
  for (final t in tables) {
    final sheet = excel[t.name];
    sheet.appendRow([for (final h in t.headers) TextCellValue(h)]);
    for (var c = 0; c < t.headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = header;
      sheet.setColumnWidth(c, c == 0 ? 22 : 18);
    }
    for (final r in t.rows) {
      sheet.appendRow([
        for (final v in r)
          switch (v) {
            null => null,
            Amount a => DoubleCellValue(a.cents / 100),
            Day d => DateCellValue(year: d.date.year, month: d.date.month, day: d.date.day),
            int i => IntCellValue(i),
            _ => TextCellValue(v.toString()),
          },
      ]);
    }
  }
  if (defaultSheet != null && !tables.any((t) => t.name == defaultSheet)) excel.delete(defaultSheet);
  excel.setDefaultSheet(tables.first.name);
  return Uint8List.fromList(excel.encode()!);
}

Uint8List buildCsv(ReportTable t) => Uint8List.fromList(utf8.encode(toCsv(t)));

/// Guarda el archivo: en la web lo descarga; en Android abre el menú para
/// compartir/guardar (Drive, Archivos, WhatsApp, correo…).
Future<void> saveFile(Uint8List bytes, String fileName, String mimeType) async {
  final file = XFile.fromData(bytes, name: fileName, mimeType: mimeType);
  if (kIsWeb) {
    await file.saveTo(fileName);
    return;
  }
  await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: [fileName], title: fileName));
}

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const csvMime = 'text/csv';
