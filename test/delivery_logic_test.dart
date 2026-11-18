import 'package:akifoods_app/core/date_range.dart';
import 'package:akifoods_app/features/delivery/delivery_logic.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryOrder o(
  String id, {
  String? loc,
  String? zone,
  String? code,
  String? storeId,
  String store = 'Дэлгүүр',
  String status = 'assigned',
  List<Map<String, dynamic>> items = const [],
  num total = 0,
  num discount = 0,
  num cash = 0,
  num transfer = 0,
  num credit = 0,
  String? seller,
  String? when,
}) =>
    DeliveryOrder({
      'id': id,
      'storeLocation': loc,
      'zone': zone,
      'storeCode': code,
      'storeId': storeId,
      'storeName': store,
      'status': status,
      'items': items,
      'totalAmount': total,
      'discountAmount': discount,
      'cashAmount': cash,
      'transferAmount': transfer,
      'creditAmount': credit,
      'sellerName': seller,
      'deliveredAt': when,
    });

void main() {
  test('optimizeRoute: ойроос хол руу, байршилгүй нь сүүлд', () {
    final stops = [
      o('far', loc: '47.95,106.95'),
      o('none'),
      o('near', loc: '47.901,106.901'),
      o('mid', loc: '47.92,106.92'),
    ];
    final r = optimizeRoute(stops, (47.9, 106.9));
    expect(r.map((x) => x.id), ['near', 'mid', 'far', 'none']);
    // Байршилгүй бол эх дараалал хэвээр.
    expect(optimizeRoute(stops, null).map((x) => x.id), ['far', 'none', 'near', 'mid']);
  });

  test('payable = нийт − хөнгөлөлт; задаргаагүй хуучин мөр', () {
    final x = DeliveryOrder({'id': '1', 'totalAmount': 10000, 'discountAmount': 500, 'paymentMethod': 'cash'});
    expect(x.payable, 9500);
    expect(paymentParts(x), [('cash', 9500)]);
  });

  group('ачаа хүлээн авах', () {
    final orders = [
      o('a', storeId: 's2', zone: 'R1', code: '20', items: [
        {'productId': 'p1', 'name': 'Тос', 'qty': 5, 'categoryName': 'Б'},
      ]),
      o('b', storeId: 's1', zone: 'R1', code: '3', items: [
        {'productId': 'p1', 'name': 'Тос', 'qty': 5, 'categoryName': 'Б'},
        {'productId': 'p2', 'name': 'Айраг', 'qty': 2, 'categoryName': 'А'},
      ]),
      // Нэг дэлгүүрийн хоёр дахь захиалга — НЭГ мөр болно.
      o('c', storeId: 's1', zone: 'R1', code: '3', items: [
        {'productId': 'p1', 'name': 'Тос', 'qty': 1, 'categoryName': 'Б'},
      ]),
    ];

    test('бүтээгдэхүүнээр нэгтгэж, дэлгүүрийг бүс → кодоор эрэмбэлнэ', () {
      final products = buildRecvProducts(orders);
      expect(products.map((p) => p.name), ['Айраг', 'Тос']);
      final oil = products[1];
      expect(oil.needQty, 11);
      expect(oil.stores.map((s) => (s.storeCode, s.qty)), [('3', 6), ('20', 5)]);
    });

    test('дутууг ХАМГИЙН СҮҮЛИЙН дэлгүүрээс хасна', () {
      final oil = buildRecvProducts(orders)[1];
      final alloc = allocateRecv(oil, 10);
      expect(alloc.map((a) => a.short), [0, 1]);
    });
  });

  group('тооцоо', () {
    const promo = Promo('Намрын', 5, null);

    test('урамшуулал зөвхөн зээлгүй төлбөрт, бүхэл төгрөгт', () {
      expect(promoDiscount(10001, promo, 0), 500);
      expect(promoDiscount(10001, promo, 1), 0);
      expect(promoDiscount(10001, null, 0), 0);
    });

    test('preset: бэлэн/данс хөнгөлөгдсөн, зээл бүтэн', () {
      expect(presetSplit('cash', 10000, promo), (9500, 0, 0));
      expect(presetSplit('transfer', 10000, promo), (0, 9500, 0));
      expect(presetSplit('credit', 10000, promo), (0, 0, 10000));
    });

    test('хуваалтын шалгалт', () {
      expect(checkSplit(total: 10000, cash: 9500, transfer: 0, credit: 0, promo: promo).state, SplitState.ok);
      // Зээл орвол хөнгөлөлт алга — 9500 нь дутуу болно.
      expect(checkSplit(total: 10000, cash: 4500, transfer: 0, credit: 5000, promo: promo).state, SplitState.short);
      expect(checkSplit(total: 10000, cash: 6000, transfer: 0, credit: 5000).state, SplitState.over);
      expect(checkSplit(total: 10000, cash: 0, transfer: 0, credit: 10000, available: 3000).state, SplitState.creditOver);
      // Баланс мэдэгдэхгүй (null) бол зээлийг ХААХГҮЙ.
      expect(checkSplit(total: 10000, cash: 0, transfer: 0, credit: 10000).state, SplitState.ok);
    });
  });

  test('түүх: борлуулагчгүй тусдаа бүлэг; буцаагдсан нь тушаах нийлбэрт орохгүй', () {
    final now = DateTime.now().toUtc().toIso8601String();
    final h = [
      o('1', status: 'delivered', total: 1000, cash: 1000, seller: 'Бат', when: now),
      o('2', status: 'returned', total: 500, when: now),
    ];
    final range = DateRange.preset(RangePreset.today);
    expect(filterHistory(h, range: range, seller: sellerNone).map((x) => x.id), ['2']);
    expect(filterHistory(h, range: range, seller: 'n:Бат').map((x) => x.id), ['1']);
    final rows = historySheetRows(h, 'Түгээгч');
    final totalRow = rows[3];
    expect(totalRow[9], 1000);
  });
}
