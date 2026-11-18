// Байршил — борлуулагч/түгээгчийн утаснаас GPS-ийг периодоор (track) болон
// үйлдлийн үед (order/settle/delivery) backend руу илгээнэ. web-ийн geo.js-ийн
// хуулбар. Алдаа гарвал чимээгүй — апп тасрахгүй.
//
// ⚠ Native апп ч гэсэн одоогоор ЗӨВХӨН апп нээлттэй үед илгээнэ (web-тэй
//   ижил). Арын горимд (апп хаалттай) илгээх бол background location
//   зөвшөөрөл + foreground service хэрэгтэй — Play Store-ийн бодлогоор
//   тусгай тайлбар шаарддаг тул дараагийн шатанд.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'format.dart';

class Coords {
  final double lat;
  final double lng;
  final double? accuracy;
  const Coords(this.lat, this.lng, [this.accuracy]);

  Map<String, double> toJson() => {'lat': lat, 'lng': lng};
}

/// /settings/schedule — ажилтны хувийн эсвэл глобал хуваарь + геофенс.
class WorkSchedule {
  final List<int> workDays; // JS getDay(): 0 = Ням … 6 = Бямба
  final String workStart;
  final String workEnd;
  final double geofenceRadiusMeters;
  final bool geofenceEnabled;
  final Map<String, dynamic> raw;

  const WorkSchedule({
    this.workDays = const [1, 2, 3, 4, 5, 6],
    this.workStart = '08:30',
    this.workEnd = '18:30',
    this.geofenceRadiusMeters = 100,
    this.geofenceEnabled = true,
    this.raw = const {},
  });

  // ⚠ Fallback нь backend settings-ийн DEFAULTS-тай ижил (08:30–18:30, Да–Бя, 100м).
  factory WorkSchedule.fromJson(Object? data, WorkSchedule fallback) {
    if (data is! Map<String, dynamic>) return fallback;
    final days = data['workDays'];
    final radius = toNum(data['geofenceRadiusMeters']);
    return WorkSchedule(
      workDays: days is List && days.isNotEmpty ? days.map((d) => toInt(d)).toList() : fallback.workDays,
      workStart: (data['workStart'] as String?) ?? fallback.workStart,
      workEnd: (data['workEnd'] as String?) ?? fallback.workEnd,
      geofenceRadiusMeters: radius > 0 ? radius.toDouble() : fallback.geofenceRadiusMeters,
      geofenceEnabled: data['geofenceEnabled'] is bool ? data['geofenceEnabled'] as bool : fallback.geofenceEnabled,
      raw: data,
    );
  }

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    return (int.tryParse(parts.first) ?? 0) * 60 + (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
  }

  bool isWorkHours([DateTime? at]) {
    final now = at ?? DateTime.now();
    // Dart weekday: Да=1 … Ня=7 → JS getDay: Ня=0.
    final jsDay = now.weekday % 7;
    if (!workDays.contains(jsDay)) return false;
    final cur = now.hour * 60 + now.minute;
    return cur >= _minutes(workStart) && cur < _minutes(workEnd);
  }
}

enum GeoAccess { granted, denied, deniedForever, serviceOff }

class GeoService extends ChangeNotifier {
  GeoService._();
  static final GeoService instance = GeoService._();

  static const Duration trackInterval = Duration(minutes: 1);
  static const Duration scheduleRefresh = Duration(minutes: 30);
  static const Duration fixReuse = Duration(seconds: 90);

  ApiClient? _api;
  WorkSchedule schedule = const WorkSchedule();
  Timer? _trackTimer;
  Timer? _scheduleTimer;
  Coords? _lastFix;
  DateTime? _lastFixAt;

  bool get geofenceEnabled => schedule.geofenceEnabled;
  double get geofenceRadius => schedule.geofenceRadiusMeters;

  Future<GeoAccess> checkAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return GeoAccess.serviceOff;
      final p = await Geolocator.checkPermission();
      return switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => GeoAccess.granted,
        LocationPermission.deniedForever => GeoAccess.deniedForever,
        _ => GeoAccess.denied,
      };
    } catch (_) {
      return GeoAccess.denied;
    }
  }

  Future<GeoAccess> requestAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return GeoAccess.serviceOff;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => GeoAccess.granted,
        LocationPermission.deniedForever => GeoAccess.deniedForever,
        _ => GeoAccess.denied,
      };
    } catch (_) {
      return GeoAccess.denied;
    }
  }

  Future<void> loadSchedule() async {
    final api = _api;
    if (api == null) return;
    try {
      schedule = WorkSchedule.fromJson(await api.get('/settings/schedule'), schedule);
      notifyListeners();
    } catch (_) {
      // Хуучин утга хэвээр.
    }
  }

  void startTracking(ApiClient api) {
    _api = api;
    loadSchedule();
    _send('track');
    _trackTimer?.cancel();
    _trackTimer = Timer.periodic(trackInterval, (_) => _send('track'));
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(scheduleRefresh, (_) => loadSchedule());
  }

  void stopTracking() {
    _trackTimer?.cancel();
    _scheduleTimer?.cancel();
    _trackTimer = null;
    _scheduleTimer = null;
    _api = null;
    _lastFix = null;
  }

  /// Тодорхой үйлдлийн агшны байршил (order / settle / delivery).
  void mark(String type) => _send(type);

  Future<void> _send(String type) async {
    final api = _api;
    if (api == null || !schedule.isWorkHours()) return; // ажлын цагийн ГАДНА илгээхгүй
    final pos = await _fresh(maxAge: const Duration(seconds: 30));
    if (pos == null) return;
    try {
      await api.post('/locations', {'lat': pos.lat, 'lng': pos.lng, 'accuracy': pos.accuracy, 'type': type});
    } catch (_) {}
  }

  Future<Coords?> _fresh({Duration maxAge = Duration.zero}) async {
    if (await checkAccess() != GeoAccess.granted) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      _lastFix = Coords(p.latitude, p.longitude, p.accuracy);
      _lastFixAt = DateTime.now();
      return _lastFix;
    } catch (e) {
      debugPrint('[geo] байршил авч чадсангүй: $e');
      return null;
    }
  }

  /// Одоогийн координат (геофенс шалгалтад үйлдэлтэй хамт сервер рүү).
  /// Background tracker-ийн 90с-аас шинэ fix байвал шууд ашиглана.
  Future<Coords?> getCoords() async {
    final at = _lastFixAt;
    if (_lastFix != null && at != null && DateTime.now().difference(at) < fixReuse) return _lastFix;
    return _fresh();
  }
}
