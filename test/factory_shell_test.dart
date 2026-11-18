import 'dart:convert';

import 'package:akifoods_app/core/api_client.dart';
import 'package:akifoods_app/core/session.dart';
import 'package:akifoods_app/features/factory/factory_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now().toUtc().toIso8601String();

final Map<String, Object> _fixtures = {
  '/orders/production-summary': {
    'totals': {
      'lockedQty': 120,
      'lockedOrderCount': 8,
      'unlockedQty': 36,
      'unlockedOrderCount': 3,
      'totalQty': 156,
      'orderCount': 11,
      'productKinds': 2,
      'deliveryCount': 2,
      'storeCount': 9,
    },
    'products': [
      {
        'productId': 'p1',
        'name': 'Шоколадтай зайрмаг 120г урт нэртэй бараа',
        'productCode': '1001',
        'unit': 'ш',
        'categoryName': 'Зайрмаг',
        'orderCount': 9,
        'totalQty: ': 0,
        'totalQty': 1240,
        'lockedQty': 1000,
        'unlockedQty': 240,
        'preparedQty': 400,
        'byDelivery': [
          {
            'deliveryUserId': 'd1',
            'deliveryName': 'Батбаяр Өлзийсайхан',
            'qty': 1000,
            'unlockedQty': 200,
            'preparedQty': 400,
          },
          {'deliveryUserId': null, 'deliveryName': null, 'qty': 240, 'unlockedQty': 40, 'preparedQty': 0},
        ],
      },
    ],
    'stores': [
      {
        'storeName': 'Өргөө',
        'storeCode': 10,
        'orderCount': 2,
        'totalQty': 30,
        'items': [
          {'name': 'Тос', 'qty': 30, 'unit': 'ш'},
        ],
      },
    ],
  },
  '/orders/production-orders': [
    {
      'id': 'o1',
      'storeName': 'Өргөө дэлгүүр маш урт нэртэй салбар',
      'storeCode': 10,
      'zone': 'R1 Баянзүрх',
      'deliveryUserId': 'd1',
      'deliveryName': 'Батбаяр Өлзийсайхан',
      'createdAt': _now,
      'lockedAt': _now,
      'handedOverAt': null,
      'items': [
        {
          'id': 'i1',
          'name': 'Шоколадтай зайрмаг 120г урт нэртэй бараа',
          'qty': 1200,
          'preparedQty': 400,
          'categoryName': 'Зайрмаг',
        },
      ],
    },
    {
      'id': 'o2',
      'storeName': 'Номин',
      'storeCode': null,
      'zone': null,
      'deliveryUserId': 'd1',
      'deliveryName': 'Батбаяр Өлзийсайхан',
      'createdAt': '2026-10-20T03:00:00Z',
      'lockedAt': null,
      'items': [
        {'id': 'i2', 'name': 'Тос', 'qty': 3, 'preparedQty': 0, 'categoryName': null},
      ],
    },
  ],
  '/factory/stock': {
    'products': [
      {'id': 'p1', 'name': 'Шоколадтай зайрмаг', 'unit': 'ш', 'balance': 0, 'hasTechCard': false},
    ],
    'materials': [
      {'id': 'm1', 'name': 'Сүү', 'unit': 'л', 'kind': 'raw', 'balance': 12.5},
      {'id': 'm2', 'name': 'Шошго 60x40', 'unit': 'ширхэг', 'kind': 'label', 'balance': 300},
    ],
  },
  '/factory/tech-cards': [
    {
      'productId': 'p1',
      'productName': 'Шоколадтай зайрмаг',
      'hasCard': true,
      'items': [
        {'materialId': 'm1', 'materialName': 'Сүү', 'qty': 0.12, 'unit': 'л'},
      ],
      'steps': ['Сүүг 80 хэм хүртэл халаана', 'Хөргөнө'],
    },
  ],
};

ApiClient _api() {
  final client = MockClient((req) async {
    final path = req.url.path.replaceFirst('/api/v1', '');
    final data = _fixtures[path];
    if (data == null) return http.Response(jsonEncode({'ok': false, 'message': 'not found'}), 404);
    return http.Response.bytes(
      utf8.encode(jsonEncode({'ok': true, 'data': data})),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return ApiClient(Session(), client: client, baseUrl: 'https://test/api/v1');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('factory табууд утасны дэлгэц дээр overflow-гүй', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final api = _api();
    await tester.pumpWidget(
      MaterialApp(
        home: FactoryShell(api: api, session: api.session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Заавал үйлдвэрлэх'), findsOneWidget);
    // Бараа болон захиалгын задаргааг нээнэ.
    final product = find.text('Шоколадтай зайрмаг 120г урт нэртэй бараа').first;
    await tester.ensureVisible(product);
    await tester.pumpAndSettle();
    await tester.tap(product);
    await tester.pumpAndSettle();
    expect(find.text('Батбаяр Өлзийсайхан'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Өргөө дэлгүүр маш урт нэртэй салбар'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Өргөө дэлгүүр маш урт нэртэй салбар'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Өргөө дэлгүүр маш урт нэртэй салбар'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final tab in ['Үлдэгдэл', 'Заавар', 'Түүх']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    expect(find.text('Гарсан барааны нэгтгэл'), findsOneWidget);
  });
}
