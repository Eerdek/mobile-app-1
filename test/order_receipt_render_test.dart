import 'dart:io';
import 'dart:ui' as ui;

import 'package:akifoods_app/printing/escpos.dart';
import 'package:akifoods_app/printing/order_receipt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  testWidgets('захиалгын баримт 576 цэгийн зураг болно (багц, урамшуулал, хуваасан төлбөр)', (tester) async {
    await _loadFont('AkiReceiptMono', ['assets/fonts/AkiReceiptMonoLatin.ttf']);
    await _loadFont('AkiReceiptMonoCyrl', [
      'assets/fonts/AkiReceiptMonoCyrl-Regular.ttf',
      'assets/fonts/AkiReceiptMonoCyrl-Bold.ttf',
    ]);
    final details = <String, dynamic>{
      'id': 'a1b2c3d4-0000',
      'createdAt': '2026-10-24T02:00:00Z',
      'deliveredAt': '2026-10-24T06:00:00Z',
      'storeCode': 1042,
      'storeName': 'Өргөө дэлгүүр',
      'storeRegister': '5327466',
      'storePhone': '99112233',
      'storeAddress': 'БЗД 26-р хороо',
      'sellerName': 'Өлзий',
      'sellerPhone': '88001122',
      'deliveryName': 'Батбаяр',
      'totalAmount': 125000,
      'discountAmount': 5000,
      'cashAmount': 100000,
      'creditAmount': 20000,
      'items': [
        {'name': 'Шоколадтай зайрмаг', 'barcode': '8654001234567', 'qty': 48, 'orderedQty': 2, 'packSize': 24, 'unitKind': 'pack', 'unitPrice': 30000, 'lineTotal': 60000, 'categoryName': 'Зайрмаг'},
        {'name': 'Тос 1л', 'qty': 5, 'unitPrice': 13000, 'lineTotal': 65000, 'categoryName': 'Тос'},
      ],
    };
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: RepaintBoundary(child: OrderReceiptDoc(details: details)),
    ))));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(RepaintBoundary)).first,
    );
    expect(boundary.size.width, dotsPerLine.toDouble());
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final out = Platform.environment['RECEIPT_PNG'];
      if (out != null) File(out).writeAsBytesSync(png);
      image.dispose();
    });
    expect(find.textContaining('2бг×24 = 48ш'), findsOneWidget);
  });
}
