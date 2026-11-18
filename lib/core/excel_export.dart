import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

// Excel файл үүсгээд утасны «Хуваалцах» цонхоор өгнө (Telegram, имэйл,
// Файл руу хадгалах г.м.). Тоонууд ЖИНХЭНЭ тоо тул Excel дээр шүүх,
// нийлбэрлэх боломжтой — web-ийн AppXlsx-тэй ижил.
Future<void> shareExcel({
  required String fileBaseName,
  required String sheetName,
  required List<List<Object>> rows,
}) async {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
  // Excel-ийн хуудасны нэр 31 тэмдэгтээс хэтрэхгүй, зарим тэмдэгт хориотой.
  final safeSheet = sheetName.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
  final name = safeSheet.length > 31 ? safeSheet.substring(0, 31) : safeSheet;
  excel.rename(defaultSheet, name);
  for (final row in rows) {
    excel.appendRow(name, [
      for (final cell in row)
        switch (cell) {
          int v => IntCellValue(v),
          num v => DoubleCellValue(v.toDouble()),
          _ => TextCellValue('$cell'),
        },
    ]);
  }
  final bytes = excel.encode();
  if (bytes == null) throw Exception('Excel файл үүсгэж чадсангүй.');
  final fileName = '$fileBaseName.xlsx';
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      fileNameOverrides: [fileName],
      subject: fileBaseName,
    ),
  );
}
