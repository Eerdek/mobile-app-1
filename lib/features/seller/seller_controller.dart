import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/session.dart';
import '../../core/ui.dart';
import 'seller_logic.dart';

/// Борлуулагчийн апп-ын төлөв. Захиалга, дэлгүүр, бараа, авлага нь бүх
/// дэлгэцэд дундаа — нэг хувь л байна (web-ийн `state`).
class SellerController extends ChangeNotifier {
  final ApiClient api;
  final AppUser user;
  SellerController(this.api, this.user);

  /// Ахлах борлуулагч — геофенс/өдөр/цаг/бүсийн хязгаарлалтгүй, түгжээ тайлна.
  bool get isSenior => user.role == 'senior';

  List<Json> orders = [];
  List<Json> stores = [];
  List<Json> products = [];
  List<Json> receivables = [];
  bool loaded = false;
  AppMessage? message;

  // ── /settings/schedule ────────────────────────────────────────────────────
  List<int> workDays = [1, 2, 3, 4, 5, 6];
  bool visitDayCheckEnabled = true;
  int? cycleWeek;
  int? cycleWeeks;
  List<String> activeZones = [];
  List<String> cycleZones = [];
  // ⚠ Анхдагч нь ЯГ серверийн анхдагч (100% ба 30 хоног). Зөвхөн UX — эцсийн
  //   эрх мэдэл сервер. Senior-т сервер 100 ба null илгээдэг.
  num returnMaxPercent = 100;
  int? returnWindowDays = 30;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void notify() {
    if (!_disposed) notifyListeners();
  }

  void setMessage(AppMessage? m) {
    message = m;
    notify();
  }

  /// Геофенс шалгалт идэвхтэй эсэх. ⚠ Senior-т ХЭЗЭЭ Ч үйлчлэхгүй (сервер мөн адил).
  bool get geofenceCheckOn => !isSenior && GeoService.instance.geofenceEnabled;

  static String errorText(Object e, String fallback) => e is ApiException ? e.message : fallback;

  // ── Ачаалал ───────────────────────────────────────────────────────────────
  Future<void> loadAll() async {
    try {
      await Future.wait([loadOrders(), loadStores(), loadProducts(), loadSchedule()]);
    } catch (e) {
      message = AppMessage.error(errorText(e, 'Өгөгдөл татахад алдаа гарлаа.'));
    }
    loaded = true;
    notify();
  }

  /// Pull-to-refresh: сүлжээний алдааг чимээгүй залгихгүй, баннерт харуулна.
  Future<void> refreshWith(Future<void> Function() load) async {
    try {
      await load();
    } catch (e) {
      setMessage(AppMessage.error(errorText(e, 'Өгөгдөл татахад алдаа гарлаа.')));
    }
  }

  Future<void> loadOrders() async {
    orders = jsonList(await api.get('/orders'));
    notify();
  }

  Future<void> loadStores() async {
    stores = jsonList(await api.get('/stores'));
    // Сонгосон дэлгүүрийн хуучин бичлэгийг шинэ хувиар солино.
    final sel = selectedStore;
    if (sel != null) {
      for (final s in stores) {
        if (s['id'] == sel['id']) selectedStore = s;
      }
    }
    notify();
    await loadReceivables();
  }

  Future<void> loadReceivables() async {
    try {
      receivables = jsonList(await api.get('/stores/my-credits'));
    } catch (_) {
      receivables = [];
    }
    notify();
  }

  Future<void> loadProducts() async {
    products = jsonList(await api.get('/products'));
    notify();
  }

  Future<void> loadSchedule() async {
    try {
      final data = await api.get('/settings/schedule');
      if (data is Json) {
        final days = data['workDays'];
        if (days is List && days.isNotEmpty) workDays = days.map((d) => toInt(d)).toList();
        if (data['visitDayCheckEnabled'] is bool) visitDayCheckEnabled = data['visitDayCheckEnabled'] as bool;
        cycleWeek = data['cycleWeek'] == null ? null : toInt(data['cycleWeek']);
        cycleWeeks = data['cycleWeeks'] == null ? null : toInt(data['cycleWeeks']);
        activeZones = data['activeZones'] is List ? (data['activeZones'] as List).map((z) => '$z').toList() : [];
        cycleZones = data['zones'] is List ? (data['zones'] as List).map((z) => '$z').toList() : [];
        // 0 бол хүчинтэй (буцаалт хаалттай).
        if (data['returnMaxPercent'] != null && num.tryParse('${data['returnMaxPercent']}') != null) {
          returnMaxPercent = toNum(data['returnMaxPercent']);
        }
        // null = хугацааны хязгааргүй (senior) — ЯГ хэвээр.
        if (data.containsKey('returnWindowDays')) {
          returnWindowDays = data['returnWindowDays'] == null ? null : toInt(data['returnWindowDays']);
        }
      }
    } catch (_) {
      // Татаж чадаагүй — default хэвээр.
    }
    notify();
  }

  // ── Дэлгүүр сонголт ───────────────────────────────────────────────────────
  Json? selectedStore;
  final Map<String, CartLine> cart = {};
  final Map<String, CartLine> returnCart = {};
  List<Json> returnProducts = [];
  String note = '';
  // Засварлаж буй захиалга {id, returnAmount} — null бол шинэ захиалга.
  ({String id, num returnAmount})? editingOrder;
  // Идемпотент түлхүүр — нэг сагсны илгээлтүүд ижил ID: сүлжээний алдаанд
  // дахин дарахад сервер давхар захиалга үүсгэхгүй.
  String? orderRequestId;
  int _returnReq = 0;

  Json? storeById(String? id) {
    for (final s in stores) {
      if (s['id'] == id) return s;
    }
    return null;
  }

  Json? productById(String? id) {
    for (final p in products) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  /// selectStore дуудагдах бүрд нэмэгдэнэ — ижил дэлгүүрийг дахин сонгосон ч
  /// (хуулах/засах) ажлын талбар «Захиалга бүртгэх» таб руу буцна.
  int storeSession = 0;

  void selectStore(String storeId) {
    final store = storeById(storeId);
    if (store == null) return;
    storeSession++;
    // Дэлгүүр солиход засварлах горим болон өмнөх сагс бүрэн цэвэрлэгдэнэ.
    editingOrder = null;
    selectedStore = store;
    cart.clear();
    returnCart.clear();
    returnProducts = [];
    orderRequestId = null;
    note = '';
    notify();
    loadReturnProducts();
  }

  void leaveStore() {
    editingOrder = null;
    selectedStore = null;
    cart.clear();
    returnCart.clear();
    orderRequestId = null;
    notify();
  }

  /// БУЦААХ БОЛОМЖИТ бараа (сүүлийн N хоногт хүргэгдсэн, өмнөх буцаалт хассан).
  /// ⚠ Хамгийн сүүлд илгээсэн хүсэлт л үр дүнгээ бичнэ.
  Future<void> loadReturnProducts() async {
    final store = selectedStore;
    if (store == null) return;
    final req = ++_returnReq;
    returnProducts = [];
    notify();
    try {
      final editing = editingOrder;
      final res = await api.get('/orders/store-products/${store['id']}', query: {'excludeOrder': editing?.id});
      if (req == _returnReq && selectedStore?['id'] == store['id']) {
        returnProducts = jsonList(res);
        notify();
      }
    } catch (_) {
      // Буцаалт заавал биш — блоклохгүй.
    }
  }

  bool get catalogLocked =>
      isCatalogLocked(selectedStore, visitDayCheckEnabled: visitDayCheckEnabled, editing: editingOrder != null);

  num get orderTotal => linesTotal(cart.values);
  num get returnTotal => linesTotal(returnCart.values);
  num get returnCapAmount => returnCap(orderTotal, returnMaxPercent);
  num get returnRoomLeft => returnCapAmount - returnTotal;

  /// Сагсанд нэмнэ. [pack] үед багцын тоог ширхэг болгоно (нэг бараа = нэг мөр).
  void addProduct(String productId, int qty, {bool pack = false}) {
    if (catalogLocked) return;
    final product = productById(productId);
    if (product == null) return;
    final amount = math.max(1, qty);
    final pieces = piecesFromInput(product, selectedStore, amount, pack: pack);
    final name = '${product['name'] ?? ''}';
    final key = cartKey(product['id'] as String?, name);
    final current = cart[key];
    cart[key] = CartLine(
      productId: product['id'] as String?,
      name: name,
      barcode: str(product['barcode']),
      unit: str(product['unit']) ?? 'ширхэг',
      qty: (current?.qty ?? 0) + pieces,
      // Сервер дахин бодож дарж бичдэг — энэ нь зөвхөн ХАРАГДАХ дүн.
      unitPrice: priceOf(product, selectedStore),
    );
    notify();
  }

  void stepCart(String key, int delta) {
    final line = cart[key];
    if (line == null) return;
    line.qty += delta;
    if (line.qty <= 0) cart.remove(key);
    notify();
  }

  void removeCart(String key) {
    cart.remove(key);
    notify();
  }

  void clearCart() {
    cart.clear();
    returnCart.clear();
    // Өөр захиалгын контекст — идемпотент түлхүүр шинэчлэгдэнэ.
    orderRequestId = null;
    notify();
  }

  /// Буцаалтын сагсанд нэмнэ. Буцаах утга: алдааны бичиг эсвэл null.
  String? addReturn(int index, int qty) {
    if (index < 0 || index >= returnProducts.length) return null;
    final product = returnProducts[index];
    final amount = math.max(1, qty);
    final name = '${product['name'] ?? ''}';
    final key = cartKey(str(product['productId']), name);
    final current = returnCart[key];
    final err = checkReturnAdd(
      name: name,
      amount: amount,
      already: current?.qty ?? 0,
      available: toInt(product['availableQty']),
      unitPrice: toNum(product['unitPrice']),
      orderTotal: orderTotal,
      returnTotal: returnTotal,
      maxPercent: returnMaxPercent,
    );
    if (err != null) return err;
    returnCart[key] = CartLine(
      productId: str(product['productId']),
      name: name,
      barcode: str(product['barcode']),
      unit: str(product['unit']) ?? 'ширхэг',
      qty: (current?.qty ?? 0) + amount,
      unitPrice: toNum(product['unitPrice']),
    );
    notify();
    return null;
  }

  void removeReturn(String key) {
    returnCart.remove(key);
    notify();
  }

  // ── Захиалга илгээх ───────────────────────────────────────────────────────
  /// Илгээхийн өмнөх шалгалт. null = илгээж болно.
  String? validateOrder() {
    final store = selectedStore;
    if (store == null) return 'Эхлээд дэлгүүр сонгоно уу.';
    if (cart.isEmpty) return 'Захиалгад хамгийн багадаа нэг бараа нэмнэ үү.';
    final subtotal = orderTotal;
    if (returnTotal > subtotal) return 'Буцаалтын дүн захиалгын нийт дүнгээс хэтэрч болохгүй.';
    // Засварлаж буй захиалгын буцаалтыг НЭМЭГДҮҮЛЭХГҮЙ бол сервер зөвшөөрдөг.
    final previous = editingOrder?.returnAmount ?? 0;
    final cap = returnCap(subtotal, returnMaxPercent);
    if (returnTotal > previous && returnTotal > cap) {
      return returnMaxPercent <= 0
          ? 'Буцаалт хаалттай байна. Админаас буцаалтын хязгаарыг нээлгэнэ үү.'
          : 'Буцаалт захиалгын дүнгийн $returnMaxPercent%-аас хэтэрч болохгүй (дээд тал нь ${formatMoney(cap)}).';
    }
    // Хуваарийн хамгаалалт — зөвхөн ШИНЭ захиалгад.
    if (editingOrder == null && visitDayCheckEnabled && visitDaysOf(store).isNotEmpty && !isTodayStore(store)) {
      if (scheduleStale(store)) {
        return 'Хуваарийн мэдээлэл өчигдрийнх байна. Дэлгүүрийн жагсаалтаа сэргээгээд дахин оролдоно уу.';
      }
      final days = visitDaysOf(store).map((d) => dayLabels[d]).join(', ');
      return scheduleBlockReason(store) == 'week'
          ? '«${str(store['zone']) ?? 'Энэ'}» бүсийн ээлж энэ долоо хоногт ирээгүй байна. Гараг нь тохирч байгаа ч мөчлөгийн дагуу өөр долоо хоногт зочилно.'
          : 'Энэ дэлгүүр өнөөдрийн маршрутад ороогүй. Хуваарийн дагуу $days өдөр л захиалга авна.';
    }
    return null;
  }

  /// Захиалга үүсгэх/шинэчлэх. Амжилттай бол хадгалсан захиалгын id.
  Future<String> submitOrder() async {
    final store = selectedStore!;
    final editing = editingOrder;
    final items = cart.values.map((l) => l.toOrderJson()).toList();
    final returns = returnCart.values.map((l) => l.toReturnJson()).toList();
    Object? saved;
    if (editing != null) {
      // Засварлах — геофенс шаардахгүй (сервер түгжээ+төлөв шалгана).
      saved = await api.put('/orders/${editing.id}', {'note': note.trim(), 'items': items, 'returnItems': returns});
    } else {
      // Геофенс: ШИНЭ захиалгыг зөвхөн дэлгүүр дээр биеэр очсон үед.
      final coords = isSenior ? null : await GeoService.instance.getCoords();
      if (coords == null && geofenceCheckOn) {
        throw const ApiException('Байршил тодорхойлж чадсангүй. GPS-ээ асааж, дэлгүүр дээрээ ирээд дахин оролдоно уу.');
      }
      orderRequestId ??= _uuid();
      saved = await api.post('/orders', {
        'storeId': store['id'],
        'lat': ?coords?.lat,
        'lng': ?coords?.lng,
        'customerName': str(store['contactName']) ?? store['name'],
        'customerPhone': store['phone'],
        'customerAddress': store['address'],
        'note': note.trim(),
        'returnItems': returns,
        'items': items,
        'clientRequestId': orderRequestId,
      });
    }
    orderRequestId = null;
    editingOrder = null;
    cart.clear();
    returnCart.clear();
    note = '';
    if (editing == null && !isSenior) GeoService.instance.mark('order');
    await loadOrders();
    return saved is Json ? '${saved['id']}' : '';
  }

  /// Захиалгыг сагсанд буулгана ("edit" эсвэл "copy"). Алдаа бол бичиг.
  Future<String?> openOrderInCart(String orderId, {required bool edit}) async {
    Json? order;
    for (final o in orders) {
      if (o['id'] == orderId) order = o;
    }
    if (order == null) return null;
    if (edit && !canModifyOrder(order)) return 'Энэ захиалга түгжигдсэн тул засах боломжгүй.';
    final details = await api.get('/orders/${Uri.encodeComponent(orderId)}');
    if (details is! Json) return 'Захиалга ачаалахад алдаа гарлаа.';
    final store = storeById(str(details['storeId']));
    if (store == null) {
      // ⚠ «Дэлгүүр устсан» гэсэн үг БИШ: GET /stores нь ЗӨВХӨН ӨӨРИЙН БҮСИЙН
      //   идэвхтэй дэлгүүрийг буцаадаг. Хоёр шалтгааныг хоёуланг нь нэрлэнэ.
      return '«${str(details['storeName']) ?? '—'}» дэлгүүр таны жагсаалтад алга байна. '
          'Уг дэлгүүр идэвхгүй болсон ЭСВЭЛ өөр БҮС рүү шилжсэн байж болзошгүй '
          '(борлуулагч зөвхөн өөрийн бүсийн дэлгүүрийг хардаг). Админаар дэлгүүрийн бүсийг шалгуулна уу.';
    }
    selectStore('${store['id']}');
    _prefill(details);
    if (edit) {
      editingOrder = (id: orderId, returnAmount: toNum(details['returnAmount']));
      // Боломжит буцаах тоог өөрийн одоогийн буцаалтыг оролцуулахгүйгээр дахин татна.
      loadReturnProducts();
    }
    message = AppMessage.success(
      edit
          ? 'Захиалгыг засаж байна — өөрчлөөд «Өөрчлөлтийг хадгалах» товчийг дарна.'
          : 'Захиалга сагсанд хуулагдлаа — тохируулаад шинэ захиалга болгож баталгаажуулна.',
    );
    notify();
    return null;
  }

  void _prefill(Json details) {
    cart.clear();
    returnCart.clear();
    for (final item in jsonList(details['items'])) {
      final productId = str(item['productId']);
      final product = productById(productId);
      final pieces = toInt(item['qty']) > 0 ? toInt(item['qty']) : 1;
      // ⚠ Каталогт байхгүй мөрд unitPrice нь ХУУЧИН багцын үнэ байж мэднэ —
      //   мөрийн НИЙТ дүнгээс нэг ширхэгийн үнийг гаргана.
      final stored = item['lineTotal'] != null ? toNum(item['lineTotal']) / pieces : toNum(item['unitPrice']);
      final name = '${item['name'] ?? ''}';
      cart[cartKey(productId, name)] = CartLine(
        productId: productId,
        name: name,
        barcode: str(item['barcode']) ?? str(product?['barcode']),
        unit: str(item['unit']) ?? str(product?['unit']) ?? 'ширхэг',
        qty: pieces,
        // Сервер ӨНӨӨДРИЙН шатлалаар дахин бодно — каталогт байгаа бол одоогийн үнэ.
        unitPrice: product != null ? priceOf(product, selectedStore) : stored,
      );
    }
    for (final item in jsonList(details['returnItems'])) {
      final name = '${item['name'] ?? ''}';
      returnCart[cartKey(str(item['productId']), name)] = CartLine(
        productId: str(item['productId']),
        name: name,
        barcode: str(item['barcode']),
        qty: toInt(item['qty']) > 0 ? toInt(item['qty']) : 1,
        unitPrice: toNum(item['unitPrice']),
      );
    }
    note = str(details['note']) ?? '';
  }

  void cancelEdit() {
    editingOrder = null;
    cart.clear();
    returnCart.clear();
    note = '';
    notify();
  }

  Future<void> deleteOrder(String orderId) async {
    await api.request('/orders/$orderId', method: 'DELETE');
    if (editingOrder?.id == orderId) cancelEdit();
    await loadOrders();
  }

  /// Senior: түгжээ тайлах / буцааж түгжих.
  Future<void> setOrderLock(String orderId, bool locked) async {
    await api.patch('/orders/$orderId/lock', {'locked': locked});
    await loadOrders();
  }

  /// Дэлгүүрийн дундаж захиалгын дүн.
  num storeAverageOrder(String storeId) {
    final list = orders.where((o) => o['storeId'] == storeId).toList();
    if (list.isEmpty) return 0;
    return (list.fold<num>(0, (s, o) => s + orderPayable(o)) / list.length).round();
  }

  /// Зээлийн мөрөөс дэлгүүрийн картыг нөхнө (өөр бүс рүү шилжсэн дэлгүүр).
  Json? creditStoreFallback(String storeId) {
    for (final row in receivables) {
      if (row['storeId'] == storeId) {
        return {
          'id': row['storeId'],
          'name': row['storeName'],
          'storeCode': row['storeCode'],
          'contactName': row['storeOwner'],
          'phone': row['storePhone'],
          'address': row['storeAddress'],
          'zone': row['storeZone'],
        };
      }
    }
    return null;
  }
}

String _uuid() {
  final r = math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, hex).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}
