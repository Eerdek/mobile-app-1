// Үйлдвэрийн цэвэр логик — web-ийн factory.js-ээс ДҮРМИЙГ нь яг хэвээр
// шилжүүлсэн. UI-гүй тул тестлэх боломжтой (test/factory_logic_test.dart).
//
// ⚠ Эрэмбийн дүрмүүд (ангилал, бүс → дэлгүүрийн код) нь серверийн
//   compareStoreRank болон web-тэй ИЖИЛ байх ёстой — зөрвөл optimistic
//   хуваарилалт ба серверийн хуваарилалт өөр дэлгүүр дүүргэж, тоо «өөрөө
//   үсэрсэн» мэт харагдана.
import 'dart:math' as math;

import '../../core/format.dart';
import 'factory_models.dart';

const String noCategory = 'Ангилалгүй';
const String zoneNone = '__none';
const String zoneNoneLabel = 'Бүсгүй (онлайн)';

// ── Батлагдсан ↔ батлагдаагүй ───────────────────────────────────────────────
// Түгжигдсэн = БАТЛАГДСАН, заавал үйлдвэрлэнэ. Түгжээгүйг борлуулагч засах,
// устгах боломжтой. Хоёрыг нийлүүлбэл үйлдвэр илүү үйлдвэрлэх эрсдэлтэй тул
// ҮРГЭЛЖ «10+4» хэлбэрээр задална.
class QtySplit {
  final int total;
  final int locked;
  final int unlocked;
  const QtySplit(this.total, this.locked, this.unlocked);

  factory QtySplit.of(int total, int unlockedQty) {
    final unlocked = math.max(0, math.min(total, unlockedQty));
    return QtySplit(total, total - unlocked, unlocked);
  }
}

QtySplit splitProduct(SummaryProduct p) => QtySplit.of(p.totalQty, p.unlockedQty);
QtySplit splitPart(DeliveryPart d) => QtySplit.of(d.qty, d.unlockedQty);

// ── Эрэмбэ ──────────────────────────────────────────────────────────────────
int _blankLast(String? a, String? b) {
  final ea = (a ?? '').trim().isEmpty;
  final eb = (b ?? '').trim().isEmpty;
  if (ea != eb) return ea ? 1 : -1;
  return 0;
}

// compareByCategory нь core/format.dart-д (баримт, түгээгч, борлуулагч бүгд нэг дүрэм).

num _codeRank(String? code) {
  if (code == null) return double.infinity;
  return num.tryParse(code) ?? double.infinity;
}

// Бүс → дэлгүүрийн код → id. Бүсгүй (онлайн) нь СҮҮЛД.
// ⚠ id нь тогтвортой сүүлчийн тулгуур — нэг дэлгүүрийн хоёр захиалга
//   санамсаргүй солигдвол 50→49 болгоход өөр захиалгаас хасагдана.
int compareOrderForPrep(ProductionOrder a, ProductionOrder b) {
  final blank = _blankLast(a.zone, b.zone);
  if (blank != 0) return blank;
  final byZone = mnCompare(a.zone ?? '', b.zone ?? '');
  if (byZone != 0) return byZone;
  final ac = _codeRank(a.storeCode);
  final bc = _codeRank(b.storeCode);
  if (ac != bc) return ac < bc ? -1 : 1;
  return a.id.compareTo(b.id);
}

// «Түгээгчид хүлээлгэн өгөх» жагсаалтын эрэмбэ: батлагдсан эхэнд, дараа нь бүс,
// дараа нь дэлгүүрийн код.
int compareOrderForHandover(ProductionOrder a, ProductionOrder b) {
  final lock = (a.isLocked ? 0 : 1) - (b.isLocked ? 0 : 1);
  if (lock != 0) return lock;
  final blank = _blankLast(a.zone, b.zone);
  if (blank != 0) return blank;
  final byZone = mnCompare(a.zone ?? '', b.zone ?? '');
  if (byZone != 0) return byZone;
  final ac = _codeRank(a.storeCode);
  final bc = _codeRank(b.storeCode);
  if (ac != bc) return ac < bc ? -1 : 1;
  return 0;
}

// ── Барааны нэгтгэлийн самбар ───────────────────────────────────────────────
class CategoryGroup {
  final String name;
  final List<SummaryProduct> items;
  final int totalQty;
  final int unlockedQty;
  const CategoryGroup(this.name, this.items, this.totalQty, this.unlockedQty);
}

List<CategoryGroup> groupByCategory(List<SummaryProduct> products) {
  final buckets = <String, List<SummaryProduct>>{};
  for (final p in products) {
    final key = (p.categoryName ?? '').trim().isEmpty ? noCategory : p.categoryName!.trim();
    buckets.putIfAbsent(key, () => []).add(p);
  }
  final groups = buckets.entries.map((e) {
    final items = [...e.value]..sort((a, b) => mnCompare(a.name, b.name));
    return CategoryGroup(
      e.key,
      items,
      items.fold(0, (s, i) => s + i.totalQty),
      items.fold(0, (s, i) => s + splitProduct(i).unlocked),
    );
  }).toList();
  groups.sort((a, b) {
    if ((a.name == noCategory) != (b.name == noCategory)) return a.name == noCategory ? 1 : -1;
    return mnCompare(a.name, b.name);
  });
  return groups;
}

// ── Optimistic бөөн бэлтгэл (бараа × түгээгч) ───────────────────────────────
// Сервертэй ЯГ ИЖИЛ гридий дүрэм: дэлгүүрийн дарааллаар нэгийг бүрэн
// дүүргээд дараагийнх руу. Буцаах утга: шинэ бэлтгэсэн тоо (олдохгүй бол null).
//
// ⚠ Захиалгын мөрийг НЭРЭЭР тааруулна — production-orders мөрөнд productId
//   байдаггүй.
int? applyLocalBulkPrep({
  required List<SummaryProduct> prepProducts,
  required List<ProductionOrder> orders,
  required String productName,
  required String deliveryKey,
  int? qty,
  bool? prepared,
}) {
  SummaryProduct? prod;
  for (final p in prepProducts) {
    if (p.name == productName) {
      prod = p;
      break;
    }
  }
  if (prod == null) return null;
  DeliveryPart? part;
  for (final d in prod.byDelivery) {
    if (d.deliveryKey == deliveryKey) {
      part = d;
      break;
    }
  }
  if (part == null) return null;

  final lockedQty = splitPart(part).locked;
  final target = qty != null
      ? math.min(lockedQty, math.max(0, qty))
      : prepared == false
      ? 0
      : lockedQty;
  part.preparedQty = target;
  prod.preparedQty = prod.byDelivery.fold(
    0,
    (sum, d) => sum + math.min(splitPart(d).locked, math.max(0, d.preparedQty)),
  );

  var remaining = target;
  final scope = orders.where((o) => o.isLocked && !o.isHanded && o.deliveryKey == deliveryKey).toList()
    ..sort(compareOrderForPrep);
  for (final order in scope) {
    for (final item in order.items) {
      if (item.name != productName) continue;
      final next = math.min(math.max(0, item.qty), math.max(0, remaining));
      item.preparedQty = next;
      remaining -= next;
    }
  }
  return target;
}

// ── Олон сонголтын шүүлтүүр ──────────────────────────────────────────────────
// ⚠ ХООСОН жагсаалт = «бүгд» — тусад нь "all" гэж хадгалахгүй.
bool selectionHas(List<String> selection, String key) => selection.isEmpty || selection.contains(key);

List<String> toggleSelection(List<String> list, String key) {
  if (key == 'all') return const [];
  return list.contains(key) ? list.where((k) => k != key).toList() : [...list, key];
}

class FilterOption {
  final String key;
  final String label;
  final int count;
  const FilterOption(this.key, this.label, this.count);
}

// ⚠ Шошгыг СОНГОЛТЫН жагсаалтын дарааллаар — дарсан дарааллаар биш.
String selectionLabel(List<FilterOption> options, List<String> selection, String allLabel) {
  if (selection.isEmpty) return allLabel;
  final picked = options.where((o) => o.key != 'all' && selection.contains(o.key)).map((o) => o.label).toList();
  return picked.isEmpty ? allLabel : picked.join(', ');
}

// ── Түгээлтийн хуудасны өгөгдөл ─────────────────────────────────────────────
// ⚠ ХҮЛЭЭГДЭЖ БУЙ захиалга л хуудсанд орно: батлагдсан БӨГӨӨД хараахан
//   хүлээлгэж өгөөгүй.
List<ProductionOrder> sheetPending(List<ProductionOrder> orders) =>
    orders.where((o) => o.isLocked && !o.isHanded).toList();

class SheetStop {
  final String name;
  final String? code;
  final String? zone;
  int orderCount = 0;
  final Set<String> days = {}; // оруулсан дарааллаар
  final Map<String, int> items = {}; // бараа → тоо (оруулсан дарааллаар)
  final Map<String, int> prep = {};
  final Map<String, String?> cats = {};

  SheetStop(this.name, this.code, this.zone);

  // ⚠ АНГИЛЛААР — бэлтгэгч агуулахыг нэг л удаа тойрох ёстой.
  List<MapEntry<String, int>> get sortedItems =>
      items.entries.toList()..sort((a, b) => compareByCategory(cats[a.key], a.key, cats[b.key], b.key));
}

int _compareStops(SheetStop a, SheetStop b) {
  final blank = _blankLast(a.zone, b.zone);
  if (blank != 0) return blank;
  final byZone = mnCompare(a.zone ?? '', b.zone ?? '');
  if (byZone != 0) return byZone;
  final ac = _codeRank(a.code);
  final bc = _codeRank(b.code);
  if (ac != bc) return ac < bc ? -1 : 1;
  return mnCompare(a.name, b.name);
}

// Нэг дэлгүүрийн олон захиалгыг НЭГ блок болгож бараагаар нь нэмнэ.
// ⚠ Код нь эрх мэдэлтэй түлхүүр — нэр давхардаж болно.
List<SheetStop> sheetStops(List<ProductionOrder> orders, List<String> days) {
  final stops = <String, SheetStop>{};
  for (final order in sheetPending(orders)) {
    if (!selectionHas(days, dayKeyOf(order.createdAt))) continue;
    final key = order.storeCode != null ? 'c${order.storeCode}' : 'n${order.storeName ?? '?'}';
    final stop = stops.putIfAbsent(key, () => SheetStop(order.storeName ?? '-', order.storeCode, order.zone));
    stop.orderCount += 1;
    stop.days.add(dayLabelOf(order.createdAt));
    for (final item in order.items) {
      stop.items[item.name] = (stop.items[item.name] ?? 0) + item.qty;
      stop.cats.putIfAbsent(item.name, () => item.categoryName);
      stop.prep[item.name] = (stop.prep[item.name] ?? 0) + item.preparedQty;
    }
  }
  return stops.values.toList()..sort(_compareStops);
}

List<FilterOption> sheetDayOptions(List<ProductionOrder> orders) {
  final pending = sheetPending(orders);
  final map = <String, (String, int)>{};
  for (final order in pending) {
    final key = dayKeyOf(order.createdAt);
    final prev = map[key];
    map[key] = (prev?.$1 ?? dayLabelOf(order.createdAt), (prev?.$2 ?? 0) + 1);
  }
  final keys = map.keys.toList()..sort();
  return [FilterOption('all', 'Бүгд', pending.length), for (final k in keys) FilterOption(k, map[k]!.$1, map[k]!.$2)];
}

// Бүсийн сонголт — СОНГОСОН ӨДРИЙН дотроос. `count` = дэлгүүрийн тоо.
List<FilterOption> sheetZoneOptions(List<ProductionOrder> orders, List<String> days) {
  final stops = sheetStops(orders, days);
  final map = <String, (String, int)>{};
  for (final stop in stops) {
    final key = stop.zone ?? zoneNone;
    final prev = map[key];
    map[key] = (prev?.$1 ?? stop.zone ?? zoneNoneLabel, (prev?.$2 ?? 0) + 1);
  }
  return [
    FilterOption('all', 'Бүх бүс', stops.length),
    for (final e in map.entries) FilterOption(e.key, e.value.$1, e.value.$2),
  ];
}

List<FilterOption> sheetDriverOptions(List<ProductionOrder> orders) {
  final map = <String, (String, int)>{};
  for (final order in sheetPending(orders)) {
    final prev = map[order.deliveryKey];
    map[order.deliveryKey] = (prev?.$1 ?? order.deliveryLabel, (prev?.$2 ?? 0) + 1);
  }
  final list = [for (final e in map.entries) FilterOption(e.key, e.value.$1, e.value.$2)];
  list.sort((a, b) => mnCompare(a.label, b.label));
  return list;
}

// ⚠ Бүсээр шүүхэд ДУГААР ӨӨРЧЛӨГДӨХГҮЙ — сонгосон өдрийн бүтэн жагсаалт
//   дахь байрлал. Бүс тус бүрээр хэвлээд дараалуулахад 1..N цоорхойгүй.
class NumberedStop {
  final SheetStop stop;
  final int no;
  const NumberedStop(this.stop, this.no);
}

List<NumberedStop> sheetVisibleStops(List<ProductionOrder> orders, List<String> days, List<String> zones) {
  final all = sheetStops(orders, days);
  return [
    for (var i = 0; i < all.length; i++)
      if (selectionHas(zones, all[i].zone ?? zoneNone)) NumberedStop(all[i], i + 1),
  ];
}

class SheetTotals {
  final List<MapEntry<String, int>> items; // ангиллаар эрэмбэлсэн
  final Map<String, int> prep;
  final Map<String, String?> cats;
  const SheetTotals(this.items, this.prep, this.cats);

  int get totalQty => items.fold(0, (s, e) => s + e.value);

  int get doneQty => items.fold(0, (s, e) => s + math.min(e.value, math.max(0, prep[e.key] ?? 0)));
}

SheetTotals sheetTotals(List<NumberedStop> rows) {
  final items = <String, int>{};
  final cats = <String, String?>{};
  final prep = <String, int>{};
  for (final row in rows) {
    row.stop.items.forEach((name, qty) {
      items[name] = (items[name] ?? 0) + qty;
      cats.putIfAbsent(name, () => row.stop.cats[name]);
    });
    row.stop.prep.forEach((name, qty) => prep[name] = (prep[name] ?? 0) + qty);
  }
  final sorted = items.entries.toList()..sort((a, b) => compareByCategory(cats[a.key], a.key, cats[b.key], b.key));
  return SheetTotals(sorted, prep, cats);
}

// Огнооны задаргаа — «08.20 · 6 захиалга  ·  08.21 · 10 захиалга».
// ⚠ ЗӨВХӨН СОНГОСОН өдрүүд.
String sheetDaySummary(List<ProductionOrder> orders, List<String> days) =>
    sheetDayOptions(orders)
        .where((d) => d.key != 'all' && selectionHas(days, d.key))
        .map((d) => '${d.label} · ${d.count} захиалга')
        .join('  ·  ');

// Мөрийн тоо — роль цаасны уртын анхааруулгад (web-тэй ижил тооцоо).
int handoverLineCount(List<NumberedStop> rows, int totalRows) =>
    6 + rows.fold<int>(0, (s, r) => s + r.stop.items.length + 3) + totalRows + 5;

int prepLineCount(SheetTotals totals) {
  final cats = totals.items.map((e) => (totals.cats[e.key] ?? '').trim()).toSet().length;
  return 8 + totals.items.length + cats;
}

// 360 мөр ≈ 99см зураг. Үүнээс урт бол принтерийн буфер хэмжигдээгүй бүсэд
// орно (bt-print.js-ийн LONG_DOC_* тайлбарыг үз).
const int sheetMaxLines = 360;

// Цаасны урт (см) — 1 мөр ≈ 2.75мм.
int sheetLengthCm(int lines) => math.max(1, (lines * 2.75 / 10).round());

// ── Excel мөрүүд ────────────────────────────────────────────────────────────
// Багана: Ангилал | Код | Бараа | Нэгж | Захиалга | Нийт | Батлагдсан |
// Батлагдаагүй | түгээгч бүрээр… · Хамгийн доор НИЙТ мөр.
List<List<Object>> buildProductExcelRows(List<SummaryProduct> products) {
  final groups = groupByCategory(products);
  final deliveryNames = {
    for (final p in products)
      for (final d in p.byDelivery) d.label,
  }.toList()..sort(mnCompare);

  final rows = <List<Object>>[
    ['Ангилал', 'Код', 'Бараа', 'Нэгж', 'Захиалга', 'Нийт тоо', 'Батлагдсан', 'Батлагдаагүй', ...deliveryNames],
  ];
  for (final group in groups) {
    for (final p in group.items) {
      final byDelivery = <String, int>{for (final d in p.byDelivery) d.label: d.qty};
      final split = splitProduct(p);
      rows.add([
        group.name,
        p.productCode ?? '',
        p.name,
        p.unitLabel,
        p.orderCount,
        split.total,
        split.locked,
        split.unlocked,
        for (final name in deliveryNames) byDelivery[name] ?? 0,
      ]);
    }
  }
  int sumAt(int index) => rows.skip(1).fold(0, (s, r) => s + (r[index] is int ? r[index] as int : 0));
  rows.add([
    'НИЙТ',
    '',
    '${rows.length - 1} нэр төрөл',
    '',
    '',
    sumAt(5),
    sumAt(6),
    sumAt(7),
    for (var i = 0; i < deliveryNames.length; i++) sumAt(8 + i),
  ]);
  return rows;
}

List<List<Object>> buildHandoverExcelRows(List<ProductionOrder> orders) {
  final rows = <List<Object>>[
    ['Түгээгч', 'Дэлгүүр', 'Бүс', 'Огноо', 'Нэр төрөл', 'Нийт ширхэг', 'Төлөв'],
  ];
  final sorted = [...orders]
    ..sort((a, b) {
      final byName = mnCompare(a.deliveryLabel, b.deliveryLabel);
      return byName != 0 ? byName : mnCompare(a.zone ?? '', b.zone ?? '');
    });
  var totalQty = 0;
  for (final o in sorted) {
    totalQty += o.totalQty;
    rows.add([
      o.deliveryLabel,
      o.storeName ?? '-',
      o.zone ?? '',
      (o.createdAt ?? '').length >= 10 ? o.createdAt!.substring(0, 10) : '',
      o.items.length,
      o.totalQty,
      o.isHanded
          ? 'Өгсөн'
          : o.isLocked
          ? 'Хүлээгдэж буй'
          : 'Батлагдаагүй',
    ]);
  }
  rows.add(['НИЙТ', '${sorted.length} захиалга', '', '', '', totalQty, '']);
  return rows;
}

// ── Бүсийн өнгө ─────────────────────────────────────────────────────────────
// ⚠ `stores.zone` ба `zones.name` хоёул ГАРААР бичигдсэн текст.
String zoneKey(String? name) => (name ?? '').trim().toLowerCase();

const List<int> zoneFallbackTones = [
  0xFF2F6FED,
  0xFF0F9D58,
  0xFFD93025,
  0xFFE8710A,
  0xFF8430CE,
  0xFF00838F,
  0xFFC2185B,
  0xFF5D4037,
];

// Админ өнгө оноогоогүй бүсэд нэрнээс нь ТОГТМОЛ өнгө — web-тэй ижил hash.
int zoneTone(String name, String? color) {
  final parsed = parseHexColor(color);
  if (parsed != null) return parsed;
  final key = zoneKey(name);
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) % 99991;
  }
  return zoneFallbackTones[hash % zoneFallbackTones.length];
}

int? parseHexColor(String? value) {
  if (value == null) return null;
  var hex = value.trim().replaceFirst('#', '');
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final n = int.tryParse(hex, radix: 16);
  return n == null ? null : 0xFF000000 | n;
}
