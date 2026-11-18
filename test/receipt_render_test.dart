import 'dart:io';
import 'dart:ui' as ui;

import 'package:akifoods_app/core/api_client.dart';
import 'package:akifoods_app/core/session.dart';
import 'package:akifoods_app/features/factory/factory_controller.dart';
import 'package:akifoods_app/features/factory/factory_models.dart';
import 'package:akifoods_app/features/factory/sheet_screen.dart';
import 'package:akifoods_app/printing/escpos.dart';
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
  testWidgets('түгээлтийн хуудас 576 цэгийн зураг болж, ESC/POS руу хөрвөнө', (tester) async {
    await _loadFont('AkiReceiptMono', ['assets/fonts/AkiReceiptMonoLatin.ttf']);
    await _loadFont('AkiReceiptMonoCyrl', [
      'assets/fonts/AkiReceiptMonoCyrl-Regular.ttf',
      'assets/fonts/AkiReceiptMonoCyrl-Bold.ttf',
    ]);

    final controller = FactoryController(ApiClient(Session()));
    controller.orders = [
      for (var i = 0; i < 4; i++)
        ProductionOrder(
          id: 'o$i',
          storeName: ['Өргөө дэлгүүр', 'Үнэнч ХХК', 'Номин 12', 'Ёроол'][i],
          storeCode: '${10 + i}',
          zone: i < 2 ? 'R1 Баянзүрх' : 'R2 Сүхбаатар',
          deliveryUserId: 'd1',
          deliveryName: 'Батбаяр',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          lockedAt: '2026-10-24T04:00:00Z',
          items: [
            ProductionItem(
              id: 'a$i',
              name: 'Шоколадтай зайрмаг 120г',
              qty: 12,
              preparedQty: i == 0 ? 12 : 4,
              categoryName: 'Зайрмаг',
            ),
            ProductionItem(id: 'b$i', name: 'Гүзээлзгэнэ', qty: 6, preparedQty: 0, categoryName: 'Жимс'),
          ],
        ),
    ];

    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(
      MaterialApp(
        home: SheetScreen(controller: controller, mode: SheetMode.handover, deliveryKey: 'd1'),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(of: find.byType(FittedBox), matching: find.byType(RepaintBoundary)).first,
    );
    expect(boundary.size.width, dotsPerLine.toDouble());

    late Uint8List png;
    late Uint8List escpos;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      expect(image.width, dotsPerLine);
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      escpos = rgbaToEscPos(rgba!.buffer.asUint8List(), image.width, image.height);
      png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      image.dispose();
    });
    expect(escpos.sublist(0, 2), [0x1b, 0x40]);
    expect(escpos.length, greaterThan(72 * 200));

    final out = Platform.environment['RECEIPT_PNG'];
    if (out != null) File(out).writeAsBytesSync(png);
  });
}
