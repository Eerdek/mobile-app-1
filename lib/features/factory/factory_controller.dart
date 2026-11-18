import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/ui.dart';
import 'factory_logic.dart';
import 'factory_models.dart';

// Бэлтгэл / хүлээлгэн өгөх / бүсийн зураг / түгээлтийн хуудас — ДӨРВҮҮЛЭЭ
// нэг өгөгдлөөс (production-summary + production-orders) уншдаг тул нэг
// controller-т байна. Хоёр хуулбар байвал нэг нь хоцорч зөрнө.
class FactoryController extends ChangeNotifier {
  final ApiClient api;
  FactoryController(this.api);

  ProductionSummary summary = ProductionSummary.empty;
  List<ProductionOrder> orders = [];
  bool loadingSummary = false;
  bool loadingOrders = false;
  bool ordersLoadedOnce = false;
  AppMessage? message;

  // Нээлттэй задаргаанууд — дахин зурагдахад хаагдахгүйн тулд ЭНД хадгална.
  final Set<String> openProducts = {};
  final Set<String> openOrders = {};

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _silentTimer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setMessage(AppMessage? value) {
    message = value;
    _notify();
  }

  void setOpen(Set<String> set, String key, bool open) {
    open ? set.add(key) : set.remove(key);
    _notify();
  }

  // ── Ачаалал ───────────────────────────────────────────────────────────────
  // Хоосон жагсаалт ба ачаалж чадаагүйг ялгаж харуулна.
  bool summaryFailed = false;
  bool ordersFailed = false;

  Future<void> loadPrepare() async {
    loadingSummary = true;
    _notify();
    try {
      summary = ProductionSummary.fromJson(await api.get('/orders/production-summary'));
      summaryFailed = false;
      _bulkFailed = false;
      message = null;
    } catch (e) {
      summary = ProductionSummary.empty;
      summaryFailed = true;
      message = AppMessage.error(_text(e, 'Бэлтгэлийн нэгтгэл ачаалахад алдаа гарлаа.'));
    } finally {
      loadingSummary = false;
      _notify();
    }
    await loadOrders();
  }

  Future<void> loadOrders() async {
    loadingOrders = true;
    _notify();
    try {
      orders = parseList(await api.get('/orders/production-orders'), ProductionOrder.fromJson);
      ordersLoadedOnce = true;
      ordersFailed = false;
    } catch (e) {
      ordersFailed = true;
      message = AppMessage.error(_text(e, 'Захиалгын жагсаалт ачаалахад алдаа гарлаа.'));
    } finally {
      loadingOrders = false;
      _notify();
    }
  }

  Future<void> ensureOrders() async {
    if (!ordersLoadedOnce) await loadOrders();
  }

  // ── Бараа × түгээгч бөөн тэмдэглэгээ ─────────────────────────────────────
  // ⚠ OPTIMISTIC: локал өгөгдлөө шууд шинэчилж зурна; сервер ард нь
  //   баталгаажуулж, бүх хүсэлт амарсны дараа НЭГ удаа чимээгүй тулгана.
  // ⚠ Бүх bulk хүсэлт НЭГ ГИНЖЭЭР дараалж явна — ижил мөрийн хоёр хүсэлт
  //   зөрж очвол хуучин утга сүүлд бичигдэнэ.
  Future<void> _bulkChain = Future.value();
  int _bulkPending = 0;
  // Bulk хүсэлт унасан ч локал (optimistic) дүр зураг хэвээр — тулгалт ч
  // бүтэлгүйтвэл хэрэглэгчид ил хэлнэ.
  bool _bulkFailed = false;
  Timer? _silentTimer;

  void bulkPrep(SummaryProduct product, DeliveryPart part, {int? qty, bool? prepared}) {
    applyLocalBulkPrep(
      prepProducts: summary.products,
      orders: orders,
      productName: product.name,
      deliveryKey: part.deliveryKey,
      qty: qty,
      prepared: prepared,
    );
    _notify();

    _bulkPending++;
    final body = <String, dynamic>{
      'productId': product.productId,
      'productName': product.productId == null ? product.name : null,
      'deliveryUserId': part.deliveryKey,
      'qty': ?qty,
      'prepared': ?prepared,
    };
    _bulkChain = _bulkChain.then((_) async {
      try {
        final res = await api.patch('/orders/production/prep-product', body);
        final handed = res is Map ? res['handedOver'] : null;
        if (handed is num && handed > 0) {
          message = AppMessage.success('$handed захиалга түгээгч рүү шилжлээ.');
        }
      } catch (e) {
        _bulkFailed = true;
        message = AppMessage.error(_text(e, 'Тэмдэглэхэд алдаа гарлаа.'));
      } finally {
        _bulkPending--;
        if (_bulkPending == 0) {
          _silentTimer?.cancel();
          _silentTimer = Timer(const Duration(milliseconds: 600), _refreshSilently);
        }
        _notify();
      }
    });
  }

  // Серверийн үнэнтэй ЧИМЭЭГҮЙ тулгана — «ачаалж байна» гэж цэвэрлэхгүй.
  Future<void> _refreshSilently() async {
    if (_bulkPending > 0 || _disposed) return;
    try {
      final s = ProductionSummary.fromJson(await api.get('/orders/production-summary'));
      final o = parseList(await api.get('/orders/production-orders'), ProductionOrder.fromJson);
      // Татаж байх зуур дахин дарсан бол ХУУЧИН дүр зургаар дарж болохгүй.
      if (_bulkPending > 0) return;
      summary = s;
      orders = o;
      _bulkFailed = false;
      _notify();
    } catch (_) {
      if (_bulkFailed) {
        message = const AppMessage.error(
          'Хадгалж чадаагүй тэмдэглэгээ дэлгэц дээр үлдсэн байж болзошгүй — доош татаж шинэчилнэ үү.',
        );
        _notify();
      }
      // Чимээгүй — дараагийн ачаалт засна.
    }
  }

  // ── Захиалгын мөр бүрийн бэлтгэл ─────────────────────────────────────────
  // ⚠ «Бүгд бэлэн → Өгсөн»-ийг СЕРВЕР шийднэ. Клиент дахин тайлбарлавал зөрнө.
  // ⚠ Нэг мөрийг хурдан дахин дарвал хүсэлтүүд ДАРААЛЖ явна (зөрж очвол хуучин
  //   утга сүүлд бичигдэнэ); алдаа гарвал зөвхөн хамгийн сүүлийн дарлт буцаана.
  final Map<String, Future<void>> _prepChain = {};
  final Map<String, int> _prepSeq = {};

  Future<void> savePrep(ProductionOrder order, ProductionItem item, int preparedQty) {
    final next = math.min(item.qty, math.max(0, preparedQty));
    final previous = item.preparedQty;
    final seq = _prepSeq[item.id] = (_prepSeq[item.id] ?? 0) + 1;
    item.preparedQty = next;
    _notify();
    final run = (_prepChain[item.id] ?? Future<void>.value()).then((_) => _sendPrep(order, item, next, previous, seq));
    _prepChain[item.id] = run;
    return run;
  }

  Future<void> _sendPrep(ProductionOrder order, ProductionItem item, int next, int previous, int seq) async {
    try {
      final res = await api.patch('/orders/${Uri.encodeComponent(order.id)}/prep-items', {
        'items': [
          {'id': item.id, 'preparedQty': next},
        ],
      });
      if (res is Map && res['allPrepared'] == true) {
        await loadOrders();
        message = const AppMessage.success('Бүгд бэлдэгдэж, түгээгчид шилжлээ.');
        _notify();
        return;
      }
      if (res is Map && res['order'] is Map) {
        order.handedOverAt = (res['order'] as Map)['handedOverAt'] as String?;
      }
      message = null;
    } catch (e) {
      if (_prepSeq[item.id] == seq) item.preparedQty = previous; // сервер татгалзвал БУЦААНА
      message = AppMessage.error(_text(e, 'Бэлтгэлийн явц хадгалахад алдаа гарлаа.'));
    }
    _notify();
  }

  // ── Хүлээлгэн өгөх ────────────────────────────────────────────────────────
  final Set<String> busyHandover = {};

  Future<void> toggleHandover(ProductionOrder order) async {
    // Батлагдаагүйг сервер чимээгүй алгасдаг — хүсэлт ч явуулахгүй.
    if (!order.isLocked || busyHandover.contains(order.id)) return;
    busyHandover.add(order.id);
    _notify();
    try {
      final res = await api.post('/orders/handover', {
        'orderIds': [order.id],
        'handed': !order.isHanded,
      });
      final updated = res is Map && res['orders'] is List && (res['orders'] as List).isNotEmpty
          ? (res['orders'] as List).first as Map
          : null;
      order.handedOverAt = updated?['handedOverAt'] as String?;
      message = null;
    } catch (e) {
      message = AppMessage.error(_text(e, 'Тэмдэглэгээ хадгалахад алдаа гарлаа.'));
    } finally {
      busyHandover.remove(order.id);
      _notify();
    }
  }

  // «Бүгдийг өгөх» / «Бүгдийг буцаах» — ЗӨВХӨН батлагдсан захиалга.
  Future<void> toggleHandoverAll(String deliveryKey) async {
    final group = orders.where((o) => o.deliveryKey == deliveryKey && o.isLocked).toList();
    if (group.isEmpty || busyHandover.contains('all:$deliveryKey')) return;
    final allHanded = group.every((o) => o.isHanded);
    final targets = allHanded ? group : group.where((o) => !o.isHanded).toList();
    busyHandover.add('all:$deliveryKey');
    _notify();
    try {
      final res = await api.post('/orders/handover', {
        'orderIds': targets.map((o) => o.id).toList(),
        'handed': !allHanded,
      });
      final byId = <String, Map>{
        if (res is Map && res['orders'] is List)
          for (final o in (res['orders'] as List).whereType<Map>()) '${o['id']}': o,
      };
      for (final o in group) {
        if (byId.containsKey(o.id)) o.handedOverAt = byId[o.id]!['handedOverAt'] as String?;
      }
      message = null;
    } catch (e) {
      message = AppMessage.error(_text(e, 'Тэмдэглэгээ хадгалахад алдаа гарлаа.'));
    } finally {
      busyHandover.remove('all:$deliveryKey');
      _notify();
    }
  }

  // ── Бүс / дэлгүүр (НЭГ УДАА л татна — үйлдвэрийн сул интернэт) ────────────
  List<ZoneRow> zones = [];
  List<StoreRow> stores = [];
  bool zonesLoaded = false;

  Future<void> loadZones() async {
    if (!zonesLoaded) {
      final results = await Future.wait([api.get('/zones'), api.get('/stores')]);
      zones = parseList(results[0], ZoneRow.fromJson);
      stores = parseList(results[1], StoreRow.fromJson);
      zonesLoaded = true;
    }
    await ensureOrders();
    _notify();
  }
}

String _text(Object error, String fallback) {
  if (error is ApiException) return error.message;
  return fallback;
}
