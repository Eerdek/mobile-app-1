import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/date_range.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/ui.dart';
import 'delivery_logic.dart';

class DeliveryController extends ChangeNotifier {
  final ApiClient api;
  final String userKey;
  DeliveryController(this.api, this.userKey);

  List<DeliveryOrder> assigned = [];
  List<DeliveryOrder> history = [];
  bool loading = false;
  bool loadedOnce = false;
  AppMessage? message;
  (double, double)? myCoords;
  bool _disposed = false;

  // Түүхийн ачаалсан цонхны эхлэл: null = бүгд. Анхдагчаар сүүлийн 90 хоног —
  // курьер олон жилийн хүргэлттэй бол мянга мянган мөр болно.
  DateTime? _historyFrom;
  bool _historyAll = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setMessage(AppMessage? m) {
    message = m;
    _notify();
  }

  String _err(Object e, String fallback) => e is ApiException ? e.message : fallback;

  Future<void> _fetchHistory(DateTime? from) async {
    final res = await api.get('/delivery/history', query: {'from': from?.toUtc().toIso8601String()});
    history = jsonList(res).map(DeliveryOrder.new).toList();
    _historyFrom = from;
    _historyAll = from == null;
  }

  Future<void> loadAll() async {
    loading = true;
    _notify();
    try {
      final from = DateTime.now().subtract(const Duration(days: 90));
      final assignedFuture = api.get('/delivery/assigned');
      await _fetchHistory(from);
      assigned = jsonList(await assignedFuture).map(DeliveryOrder.new).toList();
      loadedOnce = true;
    } catch (e) {
      message = AppMessage.error(_err(e, 'Өгөгдөл татахад алдаа гарлаа.'));
    } finally {
      loading = false;
      _notify();
    }
    // Байршлыг фонд авч, ирвэл маршрутын дараалал шинэчлэгдэнэ — жагсаалтыг
    // GPS дуустал хүлээлгэхгүй.
    refreshCoords();
  }

  Future<void> refreshCoords() async {
    final c = await GeoService.instance.getCoords();
    if (c == null) return;
    final next = (c.lat, c.lng);
    if (myCoords != next) {
      myCoords = next;
      _notify();
    }
  }

  /// Сонгосон хүрээний эхлэл ачаалсан цонхноос ӨМНӨ бол түүхийг дахин татна.
  Future<void> ensureHistoryCovers(DateRange range) async {
    if (!loadedOnce || _historyAll) return;
    final need = range.from;
    final covered = need != null && _historyFrom != null && !need.isBefore(_historyFrom!);
    if (covered) return;
    try {
      await _fetchHistory(need);
      _notify();
    } catch (e) {
      setMessage(AppMessage.error(_err(e, 'Түүх татахад алдаа гарлаа.')));
    }
  }

  DeliveryOrder? find(String id) {
    for (final o in assigned) {
      if (o.id == id) return o;
    }
    return null;
  }

  // ── Геофенс ───────────────────────────────────────────────────────────────
  /// Хүргэх/буцаах үйлдэлд координат. Геофенс асаалттай бөгөөд байршил
  /// олдохгүй бол алдаа шиднэ (сервер мөн шалгана).
  Future<Coords?> _coordsForAction({bool required = true}) async {
    final coords = await GeoService.instance.getCoords();
    if (coords == null && required && GeoService.instance.geofenceEnabled) {
      throw const ApiException('Байршил тодорхойлж чадсангүй. GPS-ээ асааж, дэлгүүр дээрээ ирээд дахин оролдоно уу.');
    }
    return coords;
  }

  // ── Тооцоо ────────────────────────────────────────────────────────────────
  Future<Promo?> fetchPromo() async {
    try {
      return Promo.fromJson(await api.get('/promotions/active'));
    } catch (_) {
      return null; // хөнгөлөлтгүй үргэлжилнэ — сервер өөрөө дахин тооцдог
    }
  }

  /// (outstanding, available) — татаж чадаагүй бол null.
  Future<(num, num?)?> fetchBalance(String storeId) async {
    try {
      final res = await api.get('/stores/${Uri.encodeComponent(storeId)}/balance');
      if (res is! Map) return null;
      final available = num.tryParse('${res['available']}');
      return (toNum(res['outstanding']), available);
    } catch (_) {
      return null;
    }
  }

  Future<void> settle(DeliveryOrder order, {required num cash, required num transfer, required num credit}) async {
    final coords = await _coordsForAction();
    await api.patch('/delivery/${Uri.encodeComponent(order.id)}/status', {
      'status': 'delivered',
      'cashAmount': cash,
      'transferAmount': transfer,
      'creditAmount': credit,
      if (coords != null) ...coords.toJson(),
    });
    GeoService.instance.mark('settle');
    await loadAll();
  }

  /// Онлайн захиалга — тооцоогүй, нэг товчоор. Төлбөрийн дүн ИЛГЭЭХГҮЙ (сервер
  /// «урьдчилж төлсөн» гэж бүртгэдэг). Геофенсээс чөлөөлөгдсөн — байршил заавал биш.
  Future<void> deliverOnline(DeliveryOrder order) async {
    final coords = await _coordsForAction(required: false);
    await api.patch('/delivery/${Uri.encodeComponent(order.id)}/status', {
      'status': 'delivered',
      if (coords != null) ...coords.toJson(),
    });
    GeoService.instance.mark('settle');
    await loadAll();
  }

  /// Тоо БУУРУУЛАХ / мөр ХАСАХ (нэмэх, өсгөх хориотой — сервер мөн шалгана).
  Future<void> saveItems(DeliveryOrder order, List<(String id, int qty)> kept) async {
    await api.patch('/delivery/${Uri.encodeComponent(order.id)}/items', {
      'items': [
        for (final k in kept) {'id': k.$1, 'qty': k.$2},
      ],
    });
    await loadAll();
  }

  /// Захиалга бүхэлдээ буруу — «буцаагдсан» руу шалтгаантай (устгалгүй).
  Future<void> returnOrder(DeliveryOrder order, String reason) async {
    final coords = await _coordsForAction();
    await api.patch('/delivery/${Uri.encodeComponent(order.id)}/status', {
      'status': 'returned',
      'returnReason': reason,
      if (coords != null) ...coords.toJson(),
    });
    await loadAll();
  }

  // ── Ачаа хүлээн авах — тоолсон тоо ────────────────────────────────────────
  // ⚠ ТҮГЭЭГЧИЙН ХУВИЙН ХЯНАЛТЫН ХУУДАС — серверт хадгалагдахгүй (хэн ч
  //   уншдаггүй хоёр дахь «үнэн» үүсгэхгүйн тулд). Утсанд, ӨДРӨӨР хугацаалж.
  Map<String, int> recvCounts = {};

  String get _recvKey => 'aki.recv.$userKey';

  Future<void> loadRecvCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recvKey);
      final parsed = raw == null ? null : jsonDecode(raw);
      // Өдөр солигдвол хуучин тооллого хүчингүй — ачаа нь өөр.
      if (parsed is Map && parsed['day'] == ymd(DateTime.now()) && parsed['counts'] is Map) {
        recvCounts = {for (final e in (parsed['counts'] as Map).entries) '${e.key}': toInt(e.value)};
      } else {
        recvCounts = {};
      }
    } catch (_) {
      recvCounts = {};
    }
    _notify();
  }

  Future<void> setRecvCount(String key, int value) async {
    if (value > 0) {
      recvCounts[key] = value;
    } else {
      recvCounts.remove(key);
    }
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recvKey, jsonEncode({'day': ymd(DateTime.now()), 'counts': recvCounts}));
    } catch (_) {}
  }
}
