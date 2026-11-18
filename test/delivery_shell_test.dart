import 'dart:convert';

import 'package:akifoods_app/core/api_client.dart';
import 'package:akifoods_app/core/session.dart';
import 'package:akifoods_app/features/delivery/delivery_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _order(String id, String store, {String status = 'assigned', String? deliveredAt, bool online = false}) => {
      'id': '$id-0000-aaaa',
      'status': status,
      'storeId': 's$id',
      'storeName': store,
      'storeCode': 10,
      'zone': 'R1 Баянзүрх',
      'storeAddress': 'БЗД 26-р хороо, 15-р байр, маш урт хаягтай дэлгүүр',
      'storePhone': '99112233',
      'storeLocation': '47.91,106.93',
      'sellerName': 'Борлуулагч Өлзий',
      'sellerPhone': '88001122',
      'source': online ? 'online' : 'seller',
      'handedOverAt': id == '1' ? null : _now,
      'totalAmount': 125000,
      'discountAmount': 0,
      'cashAmount': status == 'delivered' ? 100000 : 0,
      'transferAmount': 0,
      'creditAmount': status == 'delivered' ? 25000 : 0,
      'deliveredAt': deliveredAt,
      'assignedAt': _now,
      'items': [
        {'id': 'i$id', 'productId': 'p1', 'name': 'Шоколадтай зайрмаг 120г урт нэртэй', 'qty': 24, 'unitPrice': 2500, 'lineTotal': 60000, 'categoryName': 'Зайрмаг'},
        {'id': 'j$id', 'productId': 'p2', 'name': 'Тос', 'qty': 5, 'unitPrice': 13000, 'lineTotal': 65000, 'categoryName': null},
      ],
    };

final Map<String, Object> _fixtures = {
  '/delivery/assigned': [_order('1', 'Өргөө маш урт нэртэй дэлгүүр салбар'), _order('2', 'Номин', online: true)],
  '/delivery/history': [_order('3', 'Ёроол', status: 'delivered', deliveredAt: _now), _order('4', 'Үнэнч', status: 'returned', deliveredAt: _now)],
  '/promotions/active': {'name': 'Намрын', 'percent': 5},
  '/stores/s1/balance': {'outstanding': 50000, 'available': 200000},
  '/zones': [],
};

ApiClient _api() {
  final client = MockClient((req) async {
    final path = req.url.path.replaceFirst('/api/v1', '');
    final data = _fixtures[path];
    if (data == null) return http.Response(jsonEncode({'ok': false, 'message': 'not found'}), 404);
    return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'data': data})), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  return ApiClient(Session(), client: client, baseUrl: 'https://test/api/v1');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('түгээгчийн табууд утасны дэлгэц дээр overflow-гүй', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final api = _api();
    await tester.pumpWidget(MaterialApp(home: DeliveryShell(api: api, session: api.session)));
    await tester.pumpAndSettle();
    expect(find.text('Өнөөдөр хүргэсэн дүн'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Захиалга — карт нээж, тооцооны цонх.
    await tester.tap(find.text('Захиалга'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Өргөө маш урт нэртэй дэлгүүр салбар'));
    await tester.pumpAndSettle();
    expect(find.text('Тооцоо авах'), findsOneWidget);
    expect(find.text('Үйлдвэрээс аваагүй'), findsOneWidget);
    await tester.tap(find.text('Тооцоо авах'));
    await tester.pumpAndSettle();
    // Урамшуулал ирсний дараа бэлэн нь хөнгөлөгдсөн дүнгээр бөглөгдөнө.
    expect(find.textContaining('Намрын'), findsOneWidget);
    expect(find.text('Дүн таарлаа'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Авах дүн'))).pop();
    await tester.pumpAndSettle();

    // Засах цонх.
    await tester.tap(find.text('Засах'));
    await tester.pumpAndSettle();
    expect(find.text('Захиалга буруу — буцаах'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Шинэ барааны дүн'))).pop();
    await tester.pumpAndSettle();

    for (final tab in ['Маршрут', 'Хүлээн авах', 'Түүх']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }

    // Тайлан — blind тулгалт.
    await tester.tap(find.byTooltip('Тайлан'));
    await tester.pumpAndSettle();
    expect(find.text('•••₮'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, '99999');
    await tester.tap(find.text('Шалгах'));
    await tester.pumpAndSettle();
    expect(find.text('Дахин тоолж, зөв дүнг оруулна уу.'), findsOneWidget);
    expect(find.text('•••₮'), findsWidgets); // буруу үед ил гарахгүй
    await tester.enterText(find.byType(TextField).first, '100000');
    await tester.tap(find.text('Дахин шалгах'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Таарлаа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
