import 'dart:typed_data';

import 'package:akifoods_app/core/format.dart';
import 'package:akifoods_app/features/factory/factory_logic.dart';
import 'package:akifoods_app/features/factory/factory_models.dart';
import 'package:akifoods_app/printing/escpos.dart';
import 'package:flutter_test/flutter_test.dart';

ProductionOrder order(
  String id, {
  String? zone,
  String? code,
  String store = 'Дэлгүүр',
  String? driver = 'd1',
  bool locked = true,
  bool handed = false,
  String createdAt = '2026-10-24T03:00:00Z',
  List<ProductionItem> items = const [],
}) => ProductionOrder(
  id: id,
  zone: zone,
  storeCode: code,
  storeName: store,
  deliveryUserId: driver,
  deliveryName: driver == null ? null : 'Бат',
  createdAt: createdAt,
  lockedAt: locked ? '2026-10-24T04:00:00Z' : null,
  handedOverAt: handed ? '2026-10-24T05:00:00Z' : null,
  items: items,
);

ProductionItem item(String id, String name, int qty, {int prepared = 0, String? cat}) =>
    ProductionItem(id: id, name: name, qty: qty, preparedQty: prepared, categoryName: cat);

void main() {
  group('mnCompare', () {
    test('Ө, Ү нь монгол цагаан толгойн байрандаа (Я-гийн өмнө)', () {
      final list = ['Ян', 'Өрөм', 'Үхрийн', 'Огноо', 'Ус', 'Ёотон', 'Ердөө'];
      list.sort(mnCompare);
      expect(list, ['Ердөө', 'Ёотон', 'Огноо', 'Өрөм', 'Ус', 'Үхрийн', 'Ян']);
    });

    test('тоог тоогоор, том жижиг үсэг ялгахгүй', () {
      final list = ['Бүс 10', 'бүс 2', 'Бүс 1'];
      list.sort(mnCompare);
      expect(list, ['Бүс 1', 'бүс 2', 'Бүс 10']);
    });
  });

  test('compareByCategory: ангилалгүй нь ҮРГЭЛЖ доор', () {
    final rows = [('', 'А'), ('Тос', 'Б'), ('Ааруул', 'В')];
    rows.sort((a, b) => compareByCategory(a.$1, a.$2, b.$1, b.$2));
    expect(rows.map((r) => r.$2), ['В', 'Б', 'А']);
  });

  test('QtySplit хязгаарлалт', () {
    final s = QtySplit.of(10, 14);
    expect((s.locked, s.unlocked), (0, 10));
    final t = QtySplit.of(10, 4);
    expect((t.locked, t.unlocked), (6, 4));
  });

  group('applyLocalBulkPrep', () {
    test('дэлгүүрийн дарааллаар (бүс → код) нэгийг дүүргээд дараагийнх руу', () {
      final orders = [
        order('o3', zone: 'R2', code: '1', items: [item('i3', 'Тос', 5)]),
        order('o1', zone: 'R1', code: '20', items: [item('i1', 'Тос', 5)]),
        order('o2', zone: 'R1', code: '3', items: [item('i2', 'Тос', 5)]),
        // Гарсан ба өөр түгээгчийнх хамрах хүрээнд ОРОХГҮЙ.
        order('o4', zone: 'R1', code: '1', handed: true, items: [item('i4', 'Тос', 5)]),
        order('o5', zone: 'R1', code: '1', driver: 'd2', items: [item('i5', 'Тос', 5)]),
      ];
      final products = [
        SummaryProduct(
          name: 'Тос',
          orderCount: 3,
          totalQty: 15,
          lockedQty: 15,
          unlockedQty: 0,
          preparedQty: 0,
          byDelivery: [DeliveryPart(deliveryUserId: 'd1', qty: 15, unlockedQty: 0, preparedQty: 0)],
        ),
      ];
      final target = applyLocalBulkPrep(
        prepProducts: products,
        orders: orders,
        productName: 'Тос',
        deliveryKey: 'd1',
        qty: 7,
      );
      expect(target, 7);
      final byId = {for (final o in orders) o.id: o.items.first.preparedQty};
      expect(byId['o2'], 5); // R1 №3 эхэнд
      expect(byId['o1'], 2); // R1 №20
      expect(byId['o3'], 0); // R2
      expect(byId['o4'], 0);
      expect(byId['o5'], 0);
      expect(products.first.preparedQty, 7);
    });

    test('prepared=true нь батлагдсан хэсгээр хязгаарлагдана', () {
      final products = [
        SummaryProduct(
          name: 'Тос',
          orderCount: 1,
          totalQty: 10,
          lockedQty: 6,
          unlockedQty: 4,
          preparedQty: 0,
          byDelivery: [DeliveryPart(deliveryUserId: 'd1', qty: 10, unlockedQty: 4, preparedQty: 0)],
        ),
      ];
      final target = applyLocalBulkPrep(
        prepProducts: products,
        orders: const [],
        productName: 'Тос',
        deliveryKey: 'd1',
        prepared: true,
      );
      expect(target, 6);
    });
  });

  group('түгээлтийн хуудас', () {
    final orders = [
      order(
        'a',
        zone: 'R2',
        code: '5',
        store: 'Нэг',
        items: [item('1', 'Тос', 2, cat: 'Б')],
      ),
      order(
        'b',
        zone: 'R1',
        code: '9',
        store: 'Хоёр',
        items: [item('2', 'Айраг', 1, cat: 'А')],
      ),
      order(
        'c',
        zone: 'R1',
        code: '9',
        store: 'Хоёр',
        items: [item('3', 'Тос', 3, cat: 'Б', prepared: 3)],
      ),
      order(
        'd',
        zone: null,
        store: 'Онлайн',
        items: [item('4', 'Тос', 1, cat: 'Б')],
      ),
      order('e', zone: 'R1', code: '1', locked: false, items: [item('5', 'Тос', 9)]),
      order('f', zone: 'R1', code: '2', handed: true, items: [item('6', 'Тос', 9)]),
    ];

    test('зөвхөн батлагдсан, гараагүй; нэг дэлгүүрийг нэг блок; бүсгүй нь сүүлд', () {
      final stops = sheetStops(orders, const []);
      expect(stops.map((s) => s.name), ['Хоёр', 'Нэг', 'Онлайн']);
      expect(stops.first.orderCount, 2);
      expect(stops.first.items, {'Айраг': 1, 'Тос': 3});
    });

    test('бүсээр шүүхэд дугаар өөрчлөгдөхгүй', () {
      final rows = sheetVisibleStops(orders, const [], const ['R2']);
      expect(rows.single.no, 2);
      expect(rows.single.stop.name, 'Нэг');
    });

    test('нийт бараа ангиллаар, бэлтгэлийн явцтай', () {
      final totals = sheetTotals(sheetVisibleStops(orders, const [], const []));
      expect(totals.items.map((e) => e.key), ['Айраг', 'Тос']);
      expect(totals.totalQty, 7);
      expect(totals.doneQty, 3);
    });

    test('сонголт: хоосон = бүгд, "all" нь цэвэрлэнэ', () {
      expect(selectionHas(const [], 'x'), isTrue);
      expect(toggleSelection(['a'], 'b'), ['a', 'b']);
      expect(toggleSelection(['a', 'b'], 'a'), ['b']);
      expect(toggleSelection(['a'], 'all'), isEmpty);
    });
  });

  test('zoneTone нь тогтмол, админы өнгийг давуу үзнэ', () {
    expect(zoneTone('R1', '#ff0000'), 0xFFFF0000);
    expect(zoneTone('R1', null), zoneTone(' r1 ', null));
  });

  test('dayKeyOf локал огноогоор', () {
    final iso = DateTime(2026, 10, 24, 23, 30).toUtc().toIso8601String();
    expect(dayKeyOf(iso), '2026-10-24');
  });

  group('ESC/POS', () {
    test('толгой, band, төгсгөлийн цагаан тайралт, 0x10 солилт', () {
      const w = dotsPerLine;
      const h = 4;
      final rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
      // Мөр 0: x=3 хар → байт 0b00010000 = 0x10 → 0x30 болох ёстой.
      final p = (0 * w + 3) * 4;
      rgba[p] = 0;
      rgba[p + 1] = 0;
      rgba[p + 2] = 0;
      final bytes = rgbaToEscPos(rgba, w, h, vScale: 1);
      expect(bytes.sublist(0, 2), [0x1b, 0x40]);
      // Ганц хар мөр → 1 мөрийн band (доорх 3 цагаан мөр тайрагдана).
      expect(bytes.sublist(2, 10), [0x1d, 0x76, 0x30, 0x00, 72, 0, 1, 0]);
      expect(bytes[10], 0x30);
      expect(bytes.length, 2 + 8 + 72 + 3);
      expect(bytes.sublist(bytes.length - 3), [0x1b, 0x64, 0x04]);
    });

    test('vScale 1.25 нь мөр давхардуулж сунгана', () {
      const w = dotsPerLine;
      const h = 8;
      final rgba = Uint8List(w * h * 4); // бүгд хар (alpha=0 тул цагаан гэж тооцогдоно)
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4 + 3] = 255;
      }
      final bytes = rgbaToEscPos(rgba, w, h);
      // 8 × 1.25 = 10 мөр, бүгд хар.
      expect(bytes.sublist(2, 10), [0x1d, 0x76, 0x30, 0x00, 72, 0, 10, 0]);
    });

    test('урт баримт удаан хурдаар', () {
      expect(sendRateFor(1000), defaultSendRate);
      expect(sendRateFor(longDocBytes + 1), longDocRate);
    });
  });
}
