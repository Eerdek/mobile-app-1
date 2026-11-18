import 'package:akifoods_app/core/date_range.dart';
import 'package:akifoods_app/features/seller/seller_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final market = <String, dynamic>{'id': 's1', 'storeType': 'market'};
  final wholesale = <String, dynamic>{'id': 's2', 'storeType': 'wholesale', 'unitKinds': {'piece': true, 'pack': true}};
  final packOnly = <String, dynamic>{'id': 's3', 'storeType': 'market', 'unitKinds': {'piece': false, 'pack': true}};
  final product = <String, dynamic>{
    'id': 'p1',
    'name': 'Тос',
    'marketPrice': 1000,
    'wholesalePrice': 900,
    'defaultPrice': 1100,
    'packSize': 24,
  };

  group('үнэ, нэгж', () {
    test('дэлгүүрийн төрлөөр үнэ сонгоно, байхгүй бол defaultPrice', () {
      expect(priceOf(product, market), 1000);
      expect(priceOf(product, wholesale), 900);
      expect(priceOf({'defaultPrice': 50}, wholesale), 50);
      expect(packPriceOf(product, wholesale), 900 * 24);
    });

    test('unitKinds байхгүй бол зөвхөн ширхэг', () {
      expect(allowedUnits(market), (piece: true, pack: false));
      expect(unitFields(product, wholesale), (piece: true, pack: true));
      expect(unitFields({'packSize': 1}, wholesale).pack, isFalse); // 1 нь багц биш
    });

    test('багцаар оруулсныг ширхэг болгоно (зөвшөөрөгдсөн үед л)', () {
      expect(piecesFromInput(product, wholesale, 2, pack: true), 48);
      expect(piecesFromInput(product, market, 2, pack: true), 2);
      expect(piecesFromInput(product, wholesale, 3), 3);
    });

    test('суваг ба захиалагдах эсэх', () {
      expect(inChannel({'channelMarket': false}, market), isFalse);
      expect(inChannel({'channelMarket': false}, wholesale), isTrue);
      expect(inChannel({}, null), isTrue);
      // Ширхэг унтарсан сувагт багцгүй бараа огт гарахгүй.
      expect(isOrderable({'name': 'x'}, packOnly), isFalse);
      expect(isOrderable(product, packOnly), isTrue);
    });
  });

  group('сагс ба буцаалт', () {
    test('нийлбэр, ширхэг', () {
      final lines = [CartLine(name: 'a', qty: 2, unitPrice: 1000), CartLine(name: 'b', qty: 3, unitPrice: 500)];
      expect(linesTotal(lines), 3500);
      expect(linesPieces(lines), 5);
      expect(lines.first.toOrderJson(), {'name': 'a', 'qty': 2, 'unitPrice': 1000});
    });

    test('буцаалтын хязгаар floor-оор', () {
      expect(returnCap(999, 10), 99);
      expect(returnCap(1000, 100), 1000);
    });

    test('буцаалт нэмэх шалгалт', () {
      expect(
        checkReturnAdd(name: 'Тос', amount: 5, already: 0, available: 3, unitPrice: 100, orderTotal: 10000, returnTotal: 0, maxPercent: 100),
        contains('дээд тал нь 3'),
      );
      expect(
        checkReturnAdd(name: 'Тос', amount: 5, already: 0, available: 10, unitPrice: 100, orderTotal: 1000, returnTotal: 0, maxPercent: 30),
        contains('3 ширхэг хүртэл'),
      );
      expect(
        checkReturnAdd(name: 'Тос', amount: 2, already: 0, available: 10, unitPrice: 100, orderTotal: 1000, returnTotal: 0, maxPercent: 30),
        isNull,
      );
    });
  });

  group('хуваарь', () {
    final mon = DateTime(2026, 10, 19); // Даваа
    test('scheduledToday нь давуу', () {
      expect(isTodayStore({'scheduledToday': false, 'visitDays': [1]}, now: mon), isFalse);
      expect(isTodayStore({'visitDays': [1]}, now: mon), isTrue);
    });

    test('түгжээний шалтгаан ба түгжээ', () {
      final s = {'scheduledToday': false, 'visitDays': [1], 'zone': 'R1'};
      expect(scheduleBlockReason(s, now: mon), 'week');
      expect(scheduleBlockReason({'visitDays': [2]}, now: mon), 'day');
      expect(isCatalogLocked(s, visitDayCheckEnabled: true, editing: false, now: mon), isTrue);
      expect(isCatalogLocked(s, visitDayCheckEnabled: true, editing: true, now: mon), isFalse);
      expect(isCatalogLocked({'visitDays': []}, visitDayCheckEnabled: true, editing: false, now: mon), isFalse);
      expect(scheduleStale({'scheduleComputedFor': '2026-10-18'}, now: mon), isTrue);
    });
  });

  group('захиалга', () {
    final orders = [
      {'id': 'aaaaaaaa-1', 'storeName': 'Өргөө', 'status': 'delivered', 'totalAmount': 1000, 'discountAmount': 100, 'createdAt': DateTime.now().toIso8601String()},
      {'id': 'bbbbbbbb-2', 'storeName': 'Номин', 'status': 'assigned', 'totalAmount': 500, 'locked': false, 'createdAt': DateTime.now().toIso8601String()},
      {'id': 'cccccccc-3', 'storeName': 'Ёроол', 'status': 'returned', 'totalAmount': 700, 'createdAt': '2020-01-01T00:00:00Z'},
    ];

    test('шүүлт: Хүргээгүй нь буцаагдсаныг оруулахгүй', () {
      expect(filterMyOrders(orders, status: MyOrderStatus.undelivered).map((o) => o['id']), ['bbbbbbbb-2']);
      expect(filterMyOrders(orders, query: 'бббб').length, 0);
      expect(filterMyOrders(orders, query: 'BBBBBBBB'.toLowerCase()).length, 1);
      expect(filterMyOrders(orders, range: DateRange.preset(RangePreset.today)).length, 2);
    });

    test('засах боломж ба payable', () {
      expect(canModifyOrder(orders[1]), isTrue);
      expect(canModifyOrder({...orders[1], 'locked': true}), isFalse);
      expect(orderPayable(orders[0]), 900);
    });

    test('самбар: картууд хоорондоо нийлнэ', () {
      final s = dashStats([
        ...orders,
        {'status': 'delivered', 'totalAmount': 300, 'cashAmount': 100, 'transferAmount': 0, 'creditAmount': 200, 'createdAt': DateTime.now().toIso8601String()},
      ], const DateRange(null, null));
      expect(s.sales, s.deliveredAmount + s.pendingAmount);
      expect(s.credit, 200);
      expect(s.creditCount, 1);
    });
  });

  test('авлага: харагдац ба төлөв', () {
    final rows = [
      {'storeName': 'A', 'status': 'overdue', 'outstanding': 100, 'totalCredit': 300},
      {'storeName': 'B', 'status': 'paid', 'outstanding': 0, 'totalCredit': 200},
      {'storeName': 'C', 'status': 'normal', 'outstanding': 50, 'totalCredit': 50},
    ];
    expect(filterReceivables(rows, view: RecvView.open).map((r) => r['storeName']), ['A', 'C']);
    expect(filterReceivables(rows, view: RecvView.open, status: 'overdue').length, 1);
    expect(filterReceivables(rows, view: RecvView.paid).map((r) => r['storeName']), ['A', 'B']);
    expect(recvDueParts({'status': 'overdue', 'dueCounts': {'overdue': 2, 'warning': 1}}), ['1 ойртсон']);
  });

  group('регистр', () {
    test('латин хос кирилл болно, хэлбэр', () {
      expect(sanitizeRegister('ma71110326'), 'МА71110326');
      expect(registerKind('ma71110326'), 'person');
      expect(sanitizeRegister('53-27 4669'), '5327466');
      expect(registerKind('5327466'), 'org');
      expect(registerKind('М5'), isNull);
      expect(registerProgress('532'), 'Байгууллага — 3/7 орон');
    });

    test('маягтын шалгалт', () {
      expect(validateStoreForm(name: 'Ab', register: '1', contactName: 'Bo', phone: '991122', address: 'УБ хот', storeType: ''),
          contains('төрлийг'));
      expect(validateStoreForm(name: 'A', register: '1', contactName: 'Bo', phone: '991122', address: 'УБ', storeType: 'market'),
          contains('бүрэн бөглөнө'));
      expect(validateStoreForm(name: 'Ab', register: '1', contactName: 'Bo', phone: '991122', address: 'УБ хот', storeType: 'market'),
          isNull);
    });
  });
}
