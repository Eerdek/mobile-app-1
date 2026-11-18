// Борлуулагчийн цэвэр логик — web-ийн seller.js-ийн дүрмүүдийг яг хэвээр
// шилжүүлсэн. UI-гүй тул тестлэх боломжтой (test/seller_logic_test.dart).
//
// ⚠ Өгөгдөл нь backend-ийн JSON (Map) — талбарын нэр web-тэй ижил тул задлалгүй
//   шууд уншина. Энд байгаа функц бүр ГАНЦ эх сурвалж: UI хоёр газар өөрөөр
//   тооцвол дэлгэц ба сервер зөрнө.
import 'dart:math' as math;

import '../../core/date_range.dart';
import '../../core/format.dart';
import '../../core/units.dart';

typedef Json = Map<String, dynamic>;

String? str(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.trim().isEmpty ? null : s;
}

List<Json> jsonList(Object? v) => v is List ? v.whereType<Json>().toList() : <Json>[];

// ── Захиалга ────────────────────────────────────────────────────────────────
/// Бодит төлсөн/төлөх дүн — урамшууллын хөнгөлөлтийг хассан.
num orderPayable(Json o) => toNum(o['totalAmount']) - toNum(o['discountAmount']);

/// Цуцлагдсан/буцаагдсан захиалгыг орлогод тооцохгүй.
bool isRevenueOrder(Json o) => o['status'] != 'cancelled' && o['status'] != 'returned';

/// Засах/устгах боломж: түгжигдээгүй БА хүргэлтийн шатанд ороогүй.
bool canModifyOrder(Json o) => o['locked'] != true && (o['status'] == 'new' || o['status'] == 'assigned');

/// Борлуулагчид нэгтгэсэн төлөв: Хүргэсэн / Хүргээгүй / Буцаагдсан.
String statusLabel(Object? status) => switch (status) {
  'delivered' => 'Хүргэсэн',
  'returned' => 'Буцаагдсан',
  _ => 'Хүргээгүй',
};

enum MyOrderStatus { all, delivered, undelivered, returned }

/// Миний захиалгын шүүлт. ⚠ «Хүргээгүй» нь буцаагдсаныг ОРУУЛАХГҮЙ.
List<Json> filterMyOrders(
  List<Json> orders, {
  String query = '',
  DateRange? range,
  MyOrderStatus status = MyOrderStatus.all,
}) {
  final q = query.trim().toLowerCase();
  return orders.where((o) {
    if (q.isNotEmpty) {
      final id = '${o['id'] ?? ''}';
      final hay = [
        o['storeName'],
        id.length > 8 ? id.substring(0, 8) : id,
        o['customerName'],
        o['customerPhone'],
      ].map((v) => v ?? '').join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    if (range != null && !range.contains(o['createdAt'])) return false;
    return switch (status) {
      MyOrderStatus.all => true,
      MyOrderStatus.delivered => o['status'] == 'delivered',
      MyOrderStatus.undelivered => o['status'] != 'delivered' && o['status'] != 'returned',
      MyOrderStatus.returned => o['status'] == 'returned',
    };
  }).toList();
}

// ── Самбар ──────────────────────────────────────────────────────────────────
// ⚠ Картууд ХООРОНДОО НИЙЛДЭГ: Хүргэгдсэн + Хүлээгдэж буй = Борлуулалт,
//   Данс+Бэлэн + Зээлээр = Хүргэгдсэн. Төлбөрийн задаргаа ЗӨВХӨН хүргэгдсэнд.
class DashStats {
  final int orderCount;
  final num sales;
  final int deliveredCount;
  final num deliveredAmount;
  final int pendingCount;
  final num pendingAmount;
  final num transfer;
  final num cash;
  final int creditCount;
  final num credit;

  const DashStats({
    required this.orderCount,
    required this.sales,
    required this.deliveredCount,
    required this.deliveredAmount,
    required this.pendingCount,
    required this.pendingAmount,
    required this.transfer,
    required this.cash,
    required this.creditCount,
    required this.credit,
  });

  num get paid => transfer + cash;
}

DashStats dashStats(List<Json> orders, DateRange range) {
  final inRange = orders.where((o) => range.contains(o['createdAt'])).toList();
  final revenue = inRange.where(isRevenueOrder).toList();
  final delivered = revenue.where((o) => o['status'] == 'delivered').toList();
  final pending = revenue.where((o) => o['status'] != 'delivered').toList();
  final credit = delivered.where((o) => toNum(o['creditAmount']) > 0).toList();
  num sum(Iterable<Json> l, num Function(Json) f) => l.fold<num>(0, (s, o) => s + f(o));
  return DashStats(
    orderCount: inRange.length,
    sales: sum(revenue, orderPayable),
    deliveredCount: delivered.length,
    deliveredAmount: sum(delivered, orderPayable),
    pendingCount: pending.length,
    pendingAmount: sum(pending, orderPayable),
    transfer: sum(delivered, (o) => toNum(o['transferAmount'])),
    cash: sum(delivered, (o) => toNum(o['cashAmount'])),
    creditCount: credit.length,
    credit: sum(credit, (o) => toNum(o['creditAmount'])),
  );
}

/// Сүүлийн 6 сарын борлуулалт (хамгийн хуучнаас) — хугацааны шүүлтээс хамааралгүй.
List<(DateTime, num)> monthlySales(List<Json> orders, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return [
    for (var i = -5; i <= 0; i++)
      () {
        final m = DateTime(n.year, n.month + i, 1);
        final amount = orders
            .where((o) {
              if (!isRevenueOrder(o)) return false;
              final d = parseDate(o['createdAt']);
              return d != null && d.year == m.year && d.month == m.month;
            })
            .fold<num>(0, (s, o) => s + orderPayable(o));
        return (m, amount);
      }(),
  ];
}

// ── Хуваарь ─────────────────────────────────────────────────────────────────
const List<int> dayOrder = [1, 2, 3, 4, 5, 6, 0]; // Даваа→Ням (JS getDay)
const Map<int, String> dayLabels = {
  0: 'Ням',
  1: 'Даваа',
  2: 'Мягмар',
  3: 'Лхагва',
  4: 'Пүрэв',
  5: 'Баасан',
  6: 'Бямба',
};

int jsDay([DateTime? at]) => (at ?? DateTime.now()).weekday % 7;

List<int> visitDaysOf(Json store) =>
    store['visitDays'] is List ? (store['visitDays'] as List).map((d) => toInt(d)).toList() : const <int>[];

/// Дэлгүүр өнөөдрийн маршрутад орсон эсэх.
/// ⚠ МӨЧЛӨГИЙГ АПП ТООЦОХГҮЙ — сервер `scheduledToday`-г бэлэн илгээнэ.
///   Fallback нь хуучин гарагийн дүрэм (хуучин кэш).
bool isTodayStore(Json store, {DateTime? now}) {
  final v = store['scheduledToday'];
  if (v is bool) return v;
  return visitDaysOf(store).contains(jsDay(now));
}

/// Хаалтын шалтгаан: 'week' (бүсийн ээлж ирээгүй, гараг тохирсон) / 'day' / null.
String? scheduleBlockReason(Json store, {DateTime? now}) {
  if (isTodayStore(store, now: now)) return null;
  return visitDaysOf(store).contains(jsDay(now)) ? 'week' : 'day';
}

/// Серверийн хариу хуучирсан (апп шөнө дундыг давж нээлттэй үлдсэн).
bool scheduleStale(Json store, {DateTime? now}) {
  final forDate = str(store['scheduleComputedFor']);
  if (forDate == null) return false;
  return forDate != ymd(now ?? DateTime.now());
}

/// Каталогийн хуваарийн түгжээ. visitDays ХООСОН дэлгүүрийг хаахгүй; засварлах
/// горимд хаахгүй; админ шалгалтыг унтраасан үед хаахгүй.
bool isCatalogLocked(Json? store, {required bool visitDayCheckEnabled, required bool editing, DateTime? now}) =>
    visitDayCheckEnabled &&
    store != null &&
    !editing &&
    visitDaysOf(store).isNotEmpty &&
    !isTodayStore(store, now: now);

String scheduleLockText(Json store, {DateTime? now}) {
  final days = visitDaysOf(store).map((d) => dayLabels[d] ?? '$d').join(', ');
  if (scheduleStale(store, now: now)) return 'Хуваарийн мэдээлэл өчигдрийнх байна — жагсаалтаа сэргээнэ үү.';
  if (scheduleBlockReason(store, now: now) == 'week') {
    return '«${str(store['zone']) ?? 'Энэ'}» бүсийн ээлж энэ долоо хоногт ирээгүй байна (гараг нь тохирч байна).';
  }
  return 'Энэ дэлгүүр хуваарийн дагуу $days өдөр захиалга авна.';
}

bool storeMatchesDays(Json store, Set<int> days) => days.isEmpty || visitDaysOf(store).any(days.contains);

List<Json> filterStores(List<Json> stores, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return stores;
  return stores.where((s) {
    return [
      s['storeCode'],
      s['name'],
      s['phone'],
      s['address'],
      s['contactName'],
      s['register'],
    ].map((v) => v ?? '').join(' ').toLowerCase().contains(q);
  }).toList();
}

// ── Үнэ, нэгж, суваг ────────────────────────────────────────────────────────
/// Сонгосон дэлгүүрийн ҮНЭ — сервер бэлдсэн marketPrice / wholesalePrice-оос
/// ЗӨВХӨН сонгоно (клиент дахин бодохгүй). ⚠ Үргэлж НЭГ ШИРХЭГИЙН үнэ.
num priceOf(Json? product, Json? store) {
  if (product == null) return 0;
  final wholesale = store != null && store['storeType'] == 'wholesale';
  final price = wholesale ? product['wholesalePrice'] : product['marketPrice'];
  return toNum(price ?? product['defaultPrice']);
}

num packPriceOf(Json product, Json? store) => priceOf(product, store) * (packSizeOf(product) ?? 1);

/// ⚠ Сервер дэлгүүр бүрд `unitKinds`-ийг БЭЛНЭЭР өгдөг. Байхгүй бол ширхэг.
({bool piece, bool pack}) allowedUnits(Json? store) {
  final kinds = store?['unitKinds'];
  if (kinds is Map) return (piece: kinds['piece'] == true, pack: kinds['pack'] == true);
  return (piece: true, pack: false);
}

/// Тухайн бараанд ямар оруулах талбар гарах — багцын талбар нь ЗӨВХӨН бараанд
/// багц тохируулсан үед.
({bool piece, bool pack}) unitFields(Json product, Json? store) {
  final allow = allowedUnits(store);
  return (piece: allow.piece, pack: allow.pack && packSizeOf(product) != null);
}

/// ⚠ ХӨРВҮҮЛЭЛТИЙН ГАНЦ ЦЭГ: багцаар оруулсныг ШИРХЭГ болгоно. Үүнээс цааш
///   сагс, баримт, үйлдвэр бүгд ширхэг.
int piecesFromInput(Json product, Json? store, int amount, {bool pack = false}) {
  if (!pack) return amount;
  final size = packSizeOf(product);
  return allowedUnits(store).pack && size != null ? amount * size : amount;
}

/// ⚠ Зөвхөн ДЭЛГҮҮРИЙН сувагт зарагддаг бараа. Талбар байхгүй бол ГАРНА (`!= false`).
bool inChannel(Json product, Json? store) {
  if (store == null) return product['channelMarket'] != false || product['channelWholesale'] != false;
  return store['storeType'] == 'wholesale' ? product['channelWholesale'] != false : product['channelMarket'] != false;
}

/// Ширхэг унтарсан сувагт БАГЦГҮЙ бараа огт захиалагдахгүй.
bool isOrderable(Json product, Json? store) {
  if (!inChannel(product, store)) return false;
  if (allowedUnits(store).piece) return true;
  return product['packSize'] != null && toNum(product['packSize']) > 0;
}

String categoryKey(Json product) =>
    str(product['categoryId']) ?? 'name:${str(product['categoryName']) ?? 'Ангилалгүй'}';

const String returnCategory = '__return__';

List<Json> filterProducts(List<Json> products, Json? store, {String query = '', String category = ''}) {
  final q = query.trim().toLowerCase();
  return products.where((p) {
    if (!isOrderable(p, store)) return false;
    if (category.isNotEmpty && categoryKey(p) != category) return false;
    if (q.isEmpty) return true;
    return [
      p['productCode'],
      p['name'],
      p['categoryName'],
      p['unit'],
    ].map((v) => v ?? '').join(' ').toLowerCase().contains(q);
  }).toList();
}

/// Ангиллын сонголтууд (key → нэр), нэрээр эрэмбэлсэн.
List<(String, String)> categoryOptions(List<Json> products) {
  final seen = <String, String>{};
  for (final p in products) {
    seen.putIfAbsent(categoryKey(p), () => str(p['categoryName']) ?? 'Ангилалгүй');
  }
  return seen.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => mnCompare(a.$2, b.$2));
}

// ── Сагс ────────────────────────────────────────────────────────────────────
class CartLine {
  final String? productId;
  final String name;
  final String? barcode;
  final String unit;
  int qty; // ⚠ ҮРГЭЛЖ ФИЗИК ШИРХЭГ
  final num unitPrice;

  CartLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    this.productId,
    this.barcode,
    this.unit = 'ширхэг',
  });

  num get lineTotal => qty * unitPrice;

  Json toOrderJson() => {'productId': ?productId, 'name': name, 'qty': qty, 'unitPrice': unitPrice};

  Json toReturnJson() => {
    'productId': ?productId,
    'name': name,
    'barcode': ?barcode,
    'qty': qty,
    'unitPrice': unitPrice,
  };
}

String cartKey(String? productId, String name) => productId ?? 'name:$name';

num linesTotal(Iterable<CartLine> lines) => lines.fold<num>(0, (s, l) => s + l.lineTotal);

int linesPieces(Iterable<CartLine> lines) => lines.fold<int>(0, (s, l) => s + l.qty);

/// Буцаалтын дээд дүн. ⚠ floor — серверийн returnCapOf-той ЯГ ИЖИЛ.
num returnCap(num orderTotal, num maxPercent) => (orderTotal * maxPercent / 100).floor();

/// Буцаалт нэмж болох эсэх. Буцаах утга: null = болно, эс бөгөөс алдааны бичиг.
String? checkReturnAdd({
  required String name,
  required int amount,
  required int already,
  required int available,
  required num unitPrice,
  required num orderTotal,
  required num returnTotal,
  required num maxPercent,
}) {
  if (already + amount > available) {
    return '«$name» барааг дээд тал нь $available ширхэг буцаах боломжтой.'
        '${already > 0 ? ' Сагсанд аль хэдийн $already ширхэг нэмэгдсэн байна.' : ''}';
  }
  final room = returnCap(orderTotal, maxPercent) - returnTotal;
  if (unitPrice > 0 && amount * unitPrice > room) {
    final fits = math.max(0, (room / unitPrice).floor());
    final limit = maxPercent >= 100
        ? 'Буцаалт захиалгын дүнгээс хэтэрч болохгүй.'
        : 'Буцаалт захиалгын дүнгийн $maxPercent%-аас хэтэрч болохгүй (дээд тал нь ${formatMoney(returnCap(orderTotal, maxPercent))}).';
    return fits > 0
        ? '$limit Одоогоор «$name» барааг $fits ширхэг хүртэл нэмж болно.'
        : '$limit Илүү бараа захиалж, эсвэл буцаалтаас хасаж нэмнэ үү.';
  }
  return null;
}

// ── Авлага (/stores/my-credits) ─────────────────────────────────────────────
num recvPaidOf(Json item) => math.max(0, toNum(item['totalCredit']) - toNum(item['outstanding']));

enum RecvView { open, paid }

List<Json> filterReceivables(
  List<Json> rows, {
  required RecvView view,
  String query = '',
  String status = '',
  DateRange? range,
}) {
  final q = query.trim().toLowerCase();
  return rows.where((item) {
    // Хугацааг ТӨЛӨХ огноогоор (dueAt) — админы жагсаалттай ижил.
    if (range != null && !range.contains(item['dueAt'])) return false;
    if (q.isNotEmpty) {
      final hay = [
        item['storeName'],
        item['storeZone'],
        item['storeOwner'],
        item['storePhone'],
        item['storeAddress'],
        item['storeCode'],
      ].map((v) => v ?? '').join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    // ⚠ Харагдац нь ХАМГИЙН ГАДНА шүүлт.
    if (view == RecvView.paid) return recvPaidOf(item) > 0;
    if (item['status'] == 'paid') return false;
    return status.isEmpty || item['status'] == status;
  }).toList();
}

/// ⚠ Шошго нь ХАМГИЙН МУУ төлвийг нэрлэсэн — энд ЗӨВХӨН БУСДЫГ.
List<String> recvDueParts(Json item) {
  final counts = item['dueCounts'] is Map ? item['dueCounts'] as Map : const {};
  final worst = item['status'];
  return [
    if (toInt(counts['overdue']) > 0 && worst != 'overdue') '${toInt(counts['overdue'])} хэтэрсэн',
    if (toInt(counts['warning']) > 0 && worst != 'warning') '${toInt(counts['warning'])} ойртсон',
    if (toInt(counts['normal']) > 0 && worst != 'normal') '${toInt(counts['normal'])} хэвийн',
  ];
}

// ── Регистр (web-ийн register-lookup.js) ─────────────────────────────────────
// ⚠ Дүрэм нь backend-ийн ebarimt/register.js-тэй ЯГ ИЖИЛ байх ёстой.
final RegExp orgRegisterRe = RegExp(r'^[0-9]{7}$');
final RegExp personRegisterRe = RegExp(r'^[А-ЯЁӨҮ]{2}[0-9]{8}$');

// Гарын байрлал солиогүй үед латин «MA» → кирилл «МА». ⚠ «Y» нь У/Ү хоёрын аль
// нь ч байж болох тул ХӨРВҮҮЛЭХГҮЙ.
const Map<String, String> _latinToCyrillic = {
  'A': 'А',
  'B': 'В',
  'C': 'С',
  'E': 'Е',
  'H': 'Н',
  'K': 'К',
  'M': 'М',
  'O': 'О',
  'P': 'Р',
  'T': 'Т',
  'X': 'Х',
};

String sanitizeRegister(String value) {
  final raw = value
      .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁёӨөҮү]'), '')
      .toUpperCase()
      .replaceAllMapped(RegExp(r'[A-Z]'), (m) => _latinToCyrillic[m[0]] ?? m[0]!);
  if (raw.isEmpty) return '';
  if (RegExp(r'^[0-9]').hasMatch(raw)) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 7 ? digits.substring(0, 7) : digits;
  }
  final head = raw.substring(0, math.min(2, raw.length)).replaceAll(RegExp(r'[^А-ЯЁӨҮ]'), '');
  if (head.length < 2) return head;
  final digits = raw.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
  return head + (digits.length > 8 ? digits.substring(0, 8) : digits);
}

/// 'org' | 'person' | null
String? registerKind(String value) {
  final v = sanitizeRegister(value);
  if (orgRegisterRe.hasMatch(v)) return 'org';
  if (personRegisterRe.hasMatch(v)) return 'person';
  return null;
}

String registerProgress(String v) {
  if (v.isEmpty) return '';
  if (RegExp(r'^[0-9]').hasMatch(v)) return 'Байгууллага — ${v.length}/7 орон';
  if (v.length < 2) return 'Хувь хүн — 2 кирилл үсэг бичнэ үү';
  return 'Хувь хүн — ${v.length - 2}/8 орон';
}

/// Шинэ дэлгүүрийн маягтын шалгалт. null = зөв.
/// ⚠ Хариуцагч 2+ тэмдэгт: захиалгад customerName болж явдаг бөгөөд сервер min(2).
String? validateStoreForm({
  required String name,
  required String register,
  required String contactName,
  required String phone,
  required String address,
  required String storeType,
}) {
  if (name.length < 2 || register.isEmpty || contactName.length < 2 || phone.length < 6 || address.length < 3) {
    return 'Нэр (2+), регистр, хариуцагч (2+ тэмдэгт), утас (6+ орон), хаяг (3+ тэмдэгт) талбаруудыг бүрэн бөглөнө үү.';
  }
  if (storeType.isEmpty) return 'Дэлгүүрийн төрлийг (маркет эсвэл бөөний төв) сонгоно уу.';
  return null;
}
