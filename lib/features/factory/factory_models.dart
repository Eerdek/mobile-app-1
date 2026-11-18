import '../../core/format.dart';

// Backend-ийн хариу нь чөлөөт JSON — талбар дутуу/null ирж болно. Бүх parse
// энд төвлөрнө; бусад код нь зөвхөн эдгээр классыг хэрэглэнэ.

List<Map<String, dynamic>> _list(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

String? _str(Object? value) => value == null ? null : '$value';

// ── /orders/production-orders ────────────────────────────────────────────────
class ProductionItem {
  final String id;
  final String name;
  final int qty;
  int preparedQty; // optimistic шинэчлэлт локалаар өөрчилдөг
  final String? categoryName;

  ProductionItem({
    required this.id,
    required this.name,
    required this.qty,
    required this.preparedQty,
    this.categoryName,
  });

  factory ProductionItem.fromJson(Map<String, dynamic> j) => ProductionItem(
    id: '${j['id']}',
    name: (j['name'] ?? '') as String,
    qty: toInt(j['qty']),
    preparedQty: toInt(j['preparedQty']).clamp(0, 1 << 31),
    categoryName: _str(j['categoryName']),
  );

  bool get isPrepDone => preparedQty >= qty;
}

class ProductionOrder {
  final String id;
  final String? storeName;
  final String? storeCode;
  final String? zone;
  final String? deliveryUserId;
  final String? deliveryName;
  final String? createdAt;
  final String? lockedAt;
  String? handedOverAt;
  final List<ProductionItem> items;

  ProductionOrder({
    required this.id,
    required this.items,
    this.storeName,
    this.storeCode,
    this.zone,
    this.deliveryUserId,
    this.deliveryName,
    this.createdAt,
    this.lockedAt,
    this.handedOverAt,
  });

  factory ProductionOrder.fromJson(Map<String, dynamic> j) => ProductionOrder(
    id: '${j['id']}',
    storeName: _str(j['storeName']),
    storeCode: _str(j['storeCode']),
    zone: _nonEmpty(j['zone']),
    deliveryUserId: _nonEmpty(j['deliveryUserId']),
    deliveryName: _str(j['deliveryName']),
    createdAt: _str(j['createdAt']),
    lockedAt: _str(j['lockedAt']),
    handedOverAt: _str(j['handedOverAt']),
    items: _list(j['items']).map(ProductionItem.fromJson).toList(),
  );

  bool get isLocked => lockedAt != null;
  bool get isHanded => handedOverAt != null;

  // ⚠ "none" = түгээгч оноогоогүй — сервер яг энэ утгыг таньдаг.
  String get deliveryKey => deliveryUserId ?? 'none';
  String get deliveryLabel => deliveryName ?? 'Түгээгч оноогоогүй';

  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);
}

String? _nonEmpty(Object? value) {
  if (value == null) return null;
  final s = '$value'.trim();
  return s.isEmpty ? null : '$value';
}

// ── /orders/production-summary ──────────────────────────────────────────────
class DeliveryPart {
  final String? deliveryUserId;
  final String? deliveryName;
  final int qty;
  final int unlockedQty;
  int preparedQty;

  DeliveryPart({
    required this.qty,
    required this.unlockedQty,
    required this.preparedQty,
    this.deliveryUserId,
    this.deliveryName,
  });

  factory DeliveryPart.fromJson(Map<String, dynamic> j) => DeliveryPart(
    deliveryUserId: _nonEmpty(j['deliveryUserId']),
    deliveryName: _str(j['deliveryName']),
    qty: toInt(j['qty']),
    unlockedQty: toInt(j['unlockedQty']),
    preparedQty: toInt(j['preparedQty']),
  );

  String get deliveryKey => deliveryUserId ?? 'none';
  String get label => deliveryName ?? 'Түгээгч оноогоогүй';
}

class SummaryProduct {
  final String? productId;
  final String name;
  final String? productCode;
  final String? unit;
  final String? categoryName;
  final int orderCount;
  final int totalQty;
  final int lockedQty;
  final int unlockedQty;
  int preparedQty;
  final List<DeliveryPart> byDelivery;

  SummaryProduct({
    required this.name,
    required this.orderCount,
    required this.totalQty,
    required this.lockedQty,
    required this.unlockedQty,
    required this.preparedQty,
    required this.byDelivery,
    this.productId,
    this.productCode,
    this.unit,
    this.categoryName,
  });

  factory SummaryProduct.fromJson(Map<String, dynamic> j) => SummaryProduct(
    productId: _nonEmpty(j['productId']),
    name: (j['name'] ?? '') as String,
    productCode: _nonEmpty(j['productCode']),
    unit: _nonEmpty(j['unit']),
    categoryName: _str(j['categoryName']),
    orderCount: toInt(j['orderCount']),
    totalQty: toInt(j['totalQty']),
    lockedQty: toInt(j['lockedQty']),
    unlockedQty: toInt(j['unlockedQty']),
    preparedQty: toInt(j['preparedQty']),
    byDelivery: _list(j['byDelivery']).map(DeliveryPart.fromJson).toList(),
  );

  // Нэгж — бүртгэлтэй бараанаас; олдохгүй бол "ш" (ширхэг).
  String get unitLabel => unit ?? 'ш';
}

class SummaryStoreItem {
  final String name;
  final int qty;
  final String? unit;
  const SummaryStoreItem(this.name, this.qty, this.unit);
}

class SummaryStore {
  final String storeName;
  final String? storeCode;
  final int orderCount;
  final int totalQty;
  final List<SummaryStoreItem> items;

  const SummaryStore({
    required this.storeName,
    required this.orderCount,
    required this.totalQty,
    required this.items,
    this.storeCode,
  });

  factory SummaryStore.fromJson(Map<String, dynamic> j) => SummaryStore(
    storeName: (j['storeName'] ?? '-') as String,
    storeCode: _nonEmpty(j['storeCode']),
    orderCount: toInt(j['orderCount']),
    totalQty: toInt(j['totalQty']),
    items: _list(j['items'])
        .map((i) => SummaryStoreItem((i['name'] ?? '') as String, toInt(i['qty']), _nonEmpty(i['unit'])))
        .toList(),
  );
}

class SummaryTotals {
  final int lockedQty;
  final int lockedOrderCount;
  final int unlockedQty;
  final int unlockedOrderCount;
  final int totalQty;
  final int orderCount;
  final int productKinds;
  final int deliveryCount;
  final int storeCount;

  const SummaryTotals({
    this.lockedQty = 0,
    this.lockedOrderCount = 0,
    this.unlockedQty = 0,
    this.unlockedOrderCount = 0,
    this.totalQty = 0,
    this.orderCount = 0,
    this.productKinds = 0,
    this.deliveryCount = 0,
    this.storeCount = 0,
  });

  factory SummaryTotals.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const SummaryTotals();
    return SummaryTotals(
      lockedQty: toInt(j['lockedQty']),
      lockedOrderCount: toInt(j['lockedOrderCount']),
      unlockedQty: toInt(j['unlockedQty']),
      unlockedOrderCount: toInt(j['unlockedOrderCount']),
      totalQty: toInt(j['totalQty']),
      orderCount: toInt(j['orderCount']),
      productKinds: toInt(j['productKinds']),
      deliveryCount: toInt(j['deliveryCount']),
      storeCount: toInt(j['storeCount']),
    );
  }
}

class ProductionSummary {
  final SummaryTotals totals;
  final List<SummaryProduct> products;
  final List<SummaryStore> stores;

  const ProductionSummary({required this.totals, required this.products, required this.stores});

  factory ProductionSummary.fromJson(Object? data) {
    final j = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    return ProductionSummary(
      totals: SummaryTotals.fromJson(j['totals'] as Map<String, dynamic>?),
      products: _list(j['products']).map(SummaryProduct.fromJson).toList(),
      stores: _list(j['stores']).map(SummaryStore.fromJson).toList(),
    );
  }

  static const empty = ProductionSummary(totals: SummaryTotals(), products: [], stores: []);
}

// ── /zones, /stores ─────────────────────────────────────────────────────────
class ZoneRow {
  final String name;
  final String? color;
  final List<List<double>> polygon; // [[lat, lng], ...]

  const ZoneRow({required this.name, required this.polygon, this.color});

  factory ZoneRow.fromJson(Map<String, dynamic> j) => ZoneRow(
    name: (j['name'] ?? '') as String,
    color: _nonEmpty(j['color']),
    polygon: (j['polygon'] is List ? j['polygon'] as List : const [])
        .whereType<List>()
        .where((p) => p.length == 2)
        .map((p) => [toNum(p[0]).toDouble(), toNum(p[1]).toDouble()])
        .toList(),
  );
}

class StoreRow {
  final String? storeCode;
  final String? name;
  final String? location; // "lat,lng"
  final String? zone;

  const StoreRow({this.storeCode, this.name, this.location, this.zone});

  factory StoreRow.fromJson(Map<String, dynamic> j) => StoreRow(
    storeCode: _nonEmpty(j['storeCode']),
    name: _str(j['name']),
    location: _str(j['location']),
    zone: _nonEmpty(j['zone']),
  );

  // Байршил "47.9,106.9" хэлбэртэй — буруу бол null.
  (double, double)? get latLng {
    final parts = (location ?? '').split(',').map((v) => double.tryParse(v.trim())).toList();
    if (parts.length != 2 || parts[0] == null || parts[1] == null) return null;
    if (!parts[0]!.isFinite || !parts[1]!.isFinite) return null;
    return (parts[0]!, parts[1]!);
  }
}

// ── /factory/stock ──────────────────────────────────────────────────────────
class StockRow {
  final String id;
  final String name;
  final String? unit;
  final num balance;
  final bool isProduct;
  final bool hasTechCard;
  final String? kind; // raw | label (зөвхөн материал)

  const StockRow({
    required this.id,
    required this.name,
    required this.balance,
    required this.isProduct,
    this.unit,
    this.hasTechCard = false,
    this.kind,
  });

  factory StockRow.product(Map<String, dynamic> j) => StockRow(
    id: '${j['id']}',
    name: (j['name'] ?? '') as String,
    unit: _nonEmpty(j['unit']),
    balance: toNum(j['balance']),
    isProduct: true,
    hasTechCard: j['hasTechCard'] == true,
  );

  factory StockRow.material(Map<String, dynamic> j) => StockRow(
    id: '${j['id']}',
    name: (j['name'] ?? '') as String,
    unit: _nonEmpty(j['unit']),
    balance: toNum(j['balance']),
    isProduct: false,
    kind: _str(j['kind']),
  );
}

class StockData {
  final List<StockRow> products;
  final List<StockRow> materials;
  const StockData(this.products, this.materials);

  factory StockData.fromJson(Object? data) {
    final j = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    return StockData(
      _list(j['products']).map(StockRow.product).toList(),
      _list(j['materials']).map(StockRow.material).toList(),
    );
  }

  StockRow? find(String id) {
    for (final row in [...products, ...materials]) {
      if (row.id == id) return row;
    }
    return null;
  }
}

class StockMove {
  final num qty;
  final String reason;
  final String? note;
  final String? createdAt;
  const StockMove(this.qty, this.reason, this.note, this.createdAt);

  factory StockMove.fromJson(Map<String, dynamic> j) =>
      StockMove(toNum(j['qty']), '${j['reason'] ?? ''}', _nonEmpty(j['note']), _str(j['createdAt']));
}

// ── /factory/tech-cards ─────────────────────────────────────────────────────
class TechCardItem {
  final String materialId;
  final String materialName;
  final num qty;
  final String? unit;
  const TechCardItem(this.materialId, this.materialName, this.qty, this.unit);
}

class TechCard {
  final String productId;
  final String productName;
  final bool hasCard;
  final List<TechCardItem> items;
  final List<String> steps;
  final String? note;

  const TechCard({
    required this.productId,
    required this.productName,
    required this.hasCard,
    required this.items,
    required this.steps,
    this.note,
  });

  factory TechCard.fromJson(Map<String, dynamic> j) => TechCard(
    productId: '${j['productId']}',
    productName: (j['productName'] ?? '') as String,
    hasCard: j['hasCard'] == true,
    items: _list(j['items'])
        .map(
          (i) => TechCardItem(
            '${i['materialId']}',
            (i['materialName'] ?? '') as String,
            toNum(i['qty']),
            _nonEmpty(i['unit']),
          ),
        )
        .toList(),
    steps: (j['steps'] is List ? j['steps'] as List : const []).map((s) => '$s').toList(),
    note: _nonEmpty(j['note']),
  );
}

List<T> parseList<T>(Object? data, T Function(Map<String, dynamic>) parse) => _list(data).map(parse).toList();
