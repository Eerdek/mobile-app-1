// Түгээгчийн цэвэр логик — web-ийн delivery.js-ээс дүрмийг нь яг хэвээр.
// UI-гүй тул тестлэгдэнэ (test/delivery_logic_test.dart).
import 'dart:math' as math;

import '../../core/date_range.dart';
import '../../core/format.dart';
import '../../core/links.dart';

typedef Json = Map<String, dynamic>;

List<Json> jsonList(Object? v) => v is List ? v.whereType<Json>().toList() : <Json>[];

// ── Захиалга ────────────────────────────────────────────────────────────────
class DeliveryOrder {
  final Json raw;
  DeliveryOrder(this.raw);

  String get id => '${raw['id']}';
  String get status => '${raw['status'] ?? ''}';
  String get storeName => '${raw['storeName'] ?? raw['customerName'] ?? '-'}';
  String? get storeId => raw['storeId'] == null ? null : '${raw['storeId']}';
  String? get storeCode => raw['storeCode'] == null ? null : '${raw['storeCode']}';
  String? get zone => _blank(raw['zone']);
  String? get address => _blank(raw['storeAddress']) ?? _blank(raw['customerAddress']);
  String? get phone => _blank(raw['storePhone']) ?? _blank(raw['customerPhone']);
  String? get location => _blank(raw['storeLocation']);
  String? get sellerName => _blank(raw['sellerName']);
  String? get sellerPhone => _blank(raw['sellerPhone']);
  bool get isOnline => raw['source'] == 'online';
  bool get isHandedOver => raw['handedOverAt'] != null;
  bool get isActive => status == 'assigned' || status == 'picked_up';
  num get totalAmount => toNum(raw['totalAmount']);
  num get discountAmount => toNum(raw['discountAmount']);
  num get cashAmount => toNum(raw['cashAmount']);
  num get transferAmount => toNum(raw['transferAmount']);
  num get creditAmount => toNum(raw['creditAmount']);
  List<Json> get items => jsonList(raw['items']);

  /// Хүргэсэн бодит мөч — deliveredAt; хуучин мөрт assignedAt руу унана.
  Object? get when => raw['deliveredAt'] ?? raw['assignedAt'];

  /// Бодит төлөх дүн — урамшууллын хөнгөлөлт хассан. Хүргэсэн захиалгын
  /// Данс+Бэлэн+Зээл нийлбэр ЯГ үүнтэй тэнцэнэ.
  num get payable => totalAmount - discountAmount;

  (double, double)? get coords => parseLatLng(location);
}

String? _blank(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

const Map<String, String> paymentLabels = {'cash': 'Бэлэн', 'transfer': 'Данс', 'credit': 'Зээл'};

const Map<String, String> statusLabels = {
  'assigned': 'Оноогдсон',
  'picked_up': 'Авсан',
  'delivered': 'Хүргэсэн',
  // Admin/борлуулагчтай ижил нэршил.
  'returned': 'Буцаагдсан',
};

/// Төлбөрийн задаргаа [хэлбэр, дүн]; задаргаагүй хуучин мөрт paymentMethod-ыг бүтэн дүнгээр.
List<(String, num)> paymentParts(DeliveryOrder o) {
  final parts = <(String, num)>[];
  if (o.cashAmount > 0) parts.add(('cash', o.cashAmount));
  if (o.transferAmount > 0) parts.add(('transfer', o.transferAmount));
  if (o.creditAmount > 0) parts.add(('credit', o.creditAmount));
  final method = o.raw['paymentMethod'];
  if (parts.isEmpty && method != null) parts.add(('$method', o.payable));
  return parts;
}

// ── Маршрут ─────────────────────────────────────────────────────────────────
/// Зогсоолуудыг түгээгчийн байршлаас ОЙРООС ХОЛ руу (greedy nearest-neighbor).
/// GPS байршилгүй (зөвхөн хаягтай) зогсоолыг эцэст нь.
List<DeliveryOrder> optimizeRoute(List<DeliveryOrder> stops, (double, double)? me) {
  final located = [for (final o in stops) if (o.coords != null) o];
  final unlocated = [for (final o in stops) if (o.coords == null) o];
  if (me == null || located.isEmpty) return stops;
  final remaining = [...located];
  final result = <DeliveryOrder>[];
  var cur = me;
  while (remaining.isNotEmpty) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final c = remaining[i].coords!;
      final d = distanceMeters(cur.$1, cur.$2, c.$1, c.$2);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    final next = remaining.removeAt(best);
    result.add(next);
    cur = next.coords!;
  }
  return [...result, ...unlocated];
}

/// Хайлт: дэлгүүр / хаяг / утас / борлуулагч.
bool matchesSearch(DeliveryOrder o, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = [
    o.raw['storeName'],
    o.raw['storeAddress'],
    o.raw['customerAddress'],
    o.raw['storePhone'],
    o.raw['customerPhone'],
    o.sellerName,
    o.sellerPhone,
  ].where((v) => v != null).join(' ').toLowerCase();
  return hay.contains(q);
}

// ── Ачаа хүлээн авах ────────────────────────────────────────────────────────
class RecvStore {
  final String key;
  final String name;
  final String? storeCode;
  final String? zone;
  final bool online;
  int qty = 0;
  RecvStore(this.key, this.name, this.storeCode, this.zone, this.online);
}

class RecvProduct {
  final String key;
  final String name;
  final String? categoryName;
  final String? unit;
  final String? productCode;
  int needQty = 0;
  final Map<String, RecvStore> storeMap = {};
  List<RecvStore> stores = const [];
  RecvProduct(this.key, this.name, this.categoryName, this.unit, this.productCode);

  String get unitLabel => unit ?? 'ш';
}

num _codeRank(String? code) => code == null ? double.infinity : (num.tryParse(code) ?? double.infinity);

// ⚠ ДЭЛГҮҮРИЙН ДАРААЛАЛ нь үйлдвэрийн бэлтгэлийнхтэй ЯГ ИЖИЛ: бүс → код → түлхүүр.
//   Зөрвөл үйлдвэр нэг дэлгүүрийг дутуу гаргачхаад түгээгчийн дэлгэц ӨӨР
//   дэлгүүрийг дутуу гэж заана.
int compareRecvStore(RecvStore a, RecvStore b) {
  final ea = a.zone == null, eb = b.zone == null;
  if (ea != eb) return ea ? 1 : -1;
  final byZone = mnCompare(a.zone ?? '', b.zone ?? '');
  if (byZone != 0) return byZone;
  final ac = _codeRank(a.storeCode), bc = _codeRank(b.storeCode);
  if (ac != bc) return ac < bc ? -1 : 1;
  return a.key.compareTo(b.key);
}

/// Ачаанд байгаа барааг бүтээгдэхүүнээр нэгтгэж, дэлгүүрээр задална.
/// ⚠ Түлхүүр нь productId — ижил НЭРТЭЙ хоёр бүртгэл нийлж болохгүй.
List<RecvProduct> buildRecvProducts(List<DeliveryOrder> assigned) {
  final byProduct = <String, RecvProduct>{};
  for (final order in assigned) {
    for (final item in order.items) {
      final qty = math.max(0, toNum(item['qty']).truncate());
      if (qty == 0) continue;
      final key = item['productId'] != null ? 'id:${item['productId']}' : 'name:${item['name']}';
      final product = byProduct.putIfAbsent(
        key,
        () => RecvProduct(
          key,
          '${item['name'] ?? ''}',
          _blank(item['categoryName']),
          _blank(item['unit']),
          item['productCode'] == null ? null : '${item['productCode']}',
        ),
      );
      product.needQty += qty;
      // ⚠ Нэг дэлгүүрт хоёр захиалга — НЭГ мөр (түгээгч нэг л удаа очно).
      final storeKey = order.storeId != null ? 'id:${order.storeId}' : 'name:${order.storeName}';
      final store = product.storeMap.putIfAbsent(
        storeKey,
        () => RecvStore(storeKey, order.storeName, order.storeCode, order.zone, order.isOnline),
      );
      store.qty += qty;
    }
  }
  final list = byProduct.values.toList();
  for (final p in list) {
    p.stores = p.storeMap.values.toList()..sort(compareRecvStore);
  }
  list.sort((a, b) => compareByCategory(a.categoryName, a.name, b.categoryName, b.name));
  return list;
}

class RecvAllocation {
  final RecvStore store;
  final int got;
  int get short => store.qty - got;
  const RecvAllocation(this.store, this.got);
}

/// Тоолсон тоог дэлгүүр рүү ДАРААЛЖ хуваарилна — 50 нь 49 болоход ХАМГИЙН
/// СҮҮЛИЙН дэлгүүрээс яг 1 хасагдана (үйлдвэрийн хуваарилалттай ижил).
List<RecvAllocation> allocateRecv(RecvProduct product, int got) {
  var left = math.max(0, got);
  return [
    for (final s in product.stores)
      () {
        final take = math.min(s.qty, left);
        left -= take;
        return RecvAllocation(s, take);
      }(),
  ];
}

// ── Тооцоо (settlement) ─────────────────────────────────────────────────────
class Promo {
  final String name;
  final num percent;
  final String? description;
  const Promo(this.name, this.percent, this.description);

  static Promo? fromJson(Object? v) {
    if (v is! Json) return null;
    final percent = toNum(v['percent']);
    if (percent <= 0) return null;
    return Promo('${v['name'] ?? 'Урамшуулал'}', percent, _blank(v['description']));
  }
}

double round2(num v) => (v * 100).round() / 100;

/// Урамшууллын хөнгөлөлт — зээл ОГТ ороогүй (credit=0) төлбөрт л үйлчилнэ.
/// Сервертэй ижил: round(total × percent / 100), БҮХЭЛ төгрөгт.
num promoDiscount(num total, Promo? promo, num credit) {
  if (promo == null || promo.percent <= 0 || credit > 0) return 0;
  return (total * promo.percent / 100).round();
}

enum SplitState { ok, short, over, creditOver }

class SplitCheck {
  final SplitState state;
  final num diff; // payable − allocated
  final num discount;
  final num payable;
  const SplitCheck(this.state, this.diff, this.discount, this.payable);
}

/// Хуваасан төлбөрийн нийлбэрийг ТӨЛӨХ дүнтэй тулгана. Зээлийн хязгаарыг зөвхөн
/// баланс АМЖИЛТТАЙ ачаалагдсан үед шалгана (null = мэдэгдэхгүй → ХААХГҮЙ).
SplitCheck checkSplit({
  required num total,
  required num cash,
  required num transfer,
  required num credit,
  Promo? promo,
  num? available,
}) {
  final allocated = round2(cash + transfer + credit);
  final discount = promoDiscount(total, promo, credit);
  final payable = round2(total - discount);
  final diff = round2(payable - allocated);
  if (diff > 0) return SplitCheck(SplitState.short, diff, discount, payable);
  if (diff < 0) return SplitCheck(SplitState.over, diff, discount, payable);
  if (available != null && credit > available + 0.5) {
    return SplitCheck(SplitState.creditOver, diff, discount, payable);
  }
  return SplitCheck(SplitState.ok, diff, discount, payable);
}

/// Нэг товшилтоор бүтэн дүнг нэг хэлбэрт: бэлэн/данс → хөнгөлөгдсөн, зээл → бүтэн.
(num cash, num transfer, num credit) presetSplit(String method, num total, Promo? promo) {
  final discounted = round2(total - promoDiscount(total, promo, 0));
  return switch (method) {
    'transfer' => (0, discounted, 0),
    'credit' => (0, 0, total),
    _ => (discounted, 0, 0),
  };
}

// ── Тайлан / самбар ─────────────────────────────────────────────────────────
class MoneyTotals {
  final num cash, transfer, credit, total;
  final int count;
  const MoneyTotals(this.cash, this.transfer, this.credit, this.total, this.count);

  factory MoneyTotals.of(Iterable<DeliveryOrder> orders) {
    num cash = 0, transfer = 0, credit = 0, total = 0;
    var count = 0;
    for (final o in orders) {
      cash += o.cashAmount;
      transfer += o.transferAmount;
      credit += o.creditAmount;
      total += o.payable;
      count++;
    }
    return MoneyTotals(cash, transfer, credit, total, count);
  }
}

List<DeliveryOrder> deliveredIn(List<DeliveryOrder> history, DateRange range) {
  final list = history.where((o) => o.status == 'delivered' && range.contains(o.when)).toList();
  list.sort((a, b) => '${b.when}'.compareTo('${a.when}'));
  return list;
}

/// Сүүлийн 7 хоногийн өдөр тутмын хүргэсэн дүн (өнөөдрөөр төгсгөнө).
List<num> last7DeliveredAmounts(List<DeliveryOrder> history, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final days = List<num>.filled(7, 0);
  for (final o in history) {
    if (o.status != 'delivered') continue;
    final d = parseDate(o.when);
    if (d == null) continue;
    final diff = DateTime(today.year, today.month, today.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff >= 0 && diff < 7) days[6 - diff] += o.payable;
  }
  return days;
}

// ── Түүх ────────────────────────────────────────────────────────────────────
// ⚠ Онлайн захиалгад борлуулагч БАЙХГҮЙ — тэднийг тусад нь бүлэглэнэ. Угтвар нь
//   борлуулагчийн нэр «борлуулагчгүй»-н тэмдэгтэй ХЭЗЭЭ Ч мөргөлдөхгүйн тулд.
const String sellerNone = 'x';
String sellerKeyOf(DeliveryOrder o) => o.sellerName != null ? 'n:${o.sellerName}' : sellerNone;

List<DeliveryOrder> filterHistory(
  List<DeliveryOrder> history, {
  required DateRange range,
  String? status,
  String? seller,
}) =>
    history.where((o) {
      if (!range.contains(o.when)) return false;
      if (status != null && status.isNotEmpty && o.status != status) return false;
      if (seller != null && seller.isNotEmpty && sellerKeyOf(o) != seller) return false;
      return true;
    }).toList();

/// Хүлээлгэн өгөх хуудас (Excel) — бэлэн мөнгө ГАРААС ГАРТ шилжихэд гарын
/// үсэг зурдаг баталгаа. ⚠ БУЦААГДСАН захиалгын дүн тушаах нийлбэрт ОРОХГҮЙ.
List<List<Object>> historySheetRows(List<DeliveryOrder> orders, String courier) {
  final rows = <List<Object>>[
    ['Дугаар', 'Огноо', 'Түгээгч', 'Дэлгүүр', 'Борлуулагч', 'Данс', 'Бэлэн', 'Зээл', 'Төлөв', 'Нийт дүн'],
  ];
  num transfer = 0, cash = 0, credit = 0, total = 0;
  for (final o in orders) {
    transfer += o.transferAmount;
    cash += o.cashAmount;
    credit += o.creditAmount;
    if (o.status != 'returned') total += o.payable;
    rows.add([
      o.id.length > 8 ? o.id.substring(0, 8).toUpperCase() : o.id.toUpperCase(),
      formatDateTime(o.when),
      courier,
      o.storeName,
      o.sellerName ?? '—',
      o.transferAmount,
      o.cashAmount,
      o.creditAmount,
      statusLabels[o.status] ?? o.status,
      o.payable,
    ]);
  }
  rows.add(['', '', '', '', '', transfer, cash, credit, '', total]);
  rows.add([]);
  for (final label in ['Бэлэн тооцоог хүлээлгэж өгсөн :', 'Бэлэн тооцоог хүлээж авсан :']) {
    rows.add(['', '', '', '$label ......................................................']);
  }
  return rows;
}

/// Тайлангийн Excel: Огноо | Дэлгүүр | Данс | Бэлэн | Зээл | Нийт (+ НИЙТ мөр).
List<List<Object>> reportSheetRows(List<DeliveryOrder> orders) {
  final rows = <List<Object>>[
    ['Огноо', 'Дэлгүүр', 'Данс', 'Бэлэн', 'Зээл', 'Нийт'],
  ];
  for (final o in orders) {
    rows.add([formatDateTime(o.when), o.storeName, o.transferAmount, o.cashAmount, o.creditAmount, o.payable]);
  }
  if (orders.isNotEmpty) {
    final t = MoneyTotals.of(orders);
    rows.add(['НИЙТ', '${orders.length} захиалга', t.transfer, t.cash, t.credit, t.total]);
  }
  return rows;
}
