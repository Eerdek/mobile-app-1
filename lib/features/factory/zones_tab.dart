import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/api_client.dart';
import '../../core/ui.dart';
import '../../core/map_widgets.dart';
import 'factory_controller.dart';
import 'factory_logic.dart';
import 'factory_models.dart';

// Бүсийн зураглал — ЗӨВХӨН унших. Үйлдвэр ачаагаа маршрутын дарааллаар
// эвлүүлэхийн тулд «аль бүс хаана» гэдгийг харна. Бүс зурах/засах нь админых.
//
// ⚠ Pin дээрх ДУГААР нь түгээлтийн хуудасны дугаартай ЯГ ижил — хоёулаа
//   sheetStops()-оос гарна.
class ZonesTab extends StatefulWidget {
  final FactoryController controller;
  /// Tab руу дахин ороход shell дохио өгнө — web шиг шинэчилнэ.
  final Listenable? revisit;
  const ZonesTab({super.key, required this.controller, this.revisit});

  @override
  State<ZonesTab> createState() => _ZonesTabState();
}

class _ZoneInfo {
  final String name;
  int first;
  int last;
  int stores = 0;
  int orders = 0;
  Color color;
  final List<LatLng> points = [];
  _ZoneInfo(this.name, this.first, this.color) : last = first;
}

class _ZonesTabState extends State<ZonesTab> {
  static const _ubCenter = LatLng(47.918, 106.917);
  final MapController _map = MapController();
  AppMessage? _message;
  bool _loading = true;
  bool _expanded = false;
  bool _fitted = false;

  FactoryController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.revisit?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.revisit?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await c.loadZones();
      _message = null;
    } catch (e) {
      // ⚠ Зураг унасан ч бэлтгэлийн хуудас ажилласаар байх ёстой.
      _message = AppMessage.error(e is ApiException ? e.message : 'Бүсийн мэдээлэл ачаалахад алдаа гарлаа.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final zoneColors = {for (final z in c.zones) zoneKey(z.name): Color(zoneTone(z.name, z.color))};
        final byCode = <String, StoreRow>{};
        final byName = <String, StoreRow>{};
        for (final s in c.stores) {
          if (s.storeCode != null) byCode[s.storeCode!] = s;
          if (s.name != null) byName[s.name!] = s;
        }

        final markers = <Marker>[];
        final allPoints = <LatLng>[];
        final zones = <String, _ZoneInfo>{};
        final activeZones = <String>{};
        var missing = 0;
        final stops = sheetStops(c.orders, const []);
        for (var i = 0; i < stops.length; i++) {
          final stop = stops[i];
          final no = i + 1;
          final zoneName = stop.zone ?? zoneNoneLabel;
          final store = (stop.code != null ? byCode[stop.code] : null) ?? byName[stop.name];
          final zone = stop.zone ?? store?.zone;
          final color = zoneColors[zoneKey(zone)] ?? const Color(0xFF64748B);
          final info = zones.putIfAbsent(zoneName, () => _ZoneInfo(zoneName, no, color));
          info.last = no;
          info.stores += 1;
          info.orders += stop.orderCount;
          final ll = store?.latLng;
          // ⚠ Зурагт багтаагүй зогсоолыг ЧИМЭЭГҮЙ орхихгүй — тоолж хэлнэ.
          if (ll == null) {
            missing++;
            continue;
          }
          info.color = color;
          if (zone != null) activeZones.add(zoneKey(zone));
          final point = LatLng(ll.$1, ll.$2);
          allPoints.add(point);
          info.points.add(point);
          markers.add(
            Marker(
              point: point,
              width: 28,
              height: 36,
              alignment: Alignment.topCenter, // дуслын үзүүр координат дээр
              child: GestureDetector(
                onTap: () => _showStop(no, stop, zoneName),
                child: NumberPin(color: color, number: no),
              ),
            ),
          );
        }

        // Ачаатай бүс ТОДООР, ачаагүй нь бүдгээр.
        final polygons = <Polygon>[
          for (final z in c.zones)
            if (z.polygon.length >= 3)
              () {
                final color = zoneColors[zoneKey(z.name)] ?? const Color(0xFF64748B);
                final active = activeZones.contains(zoneKey(z.name));
                return Polygon(
                  points: [for (final p in z.polygon) LatLng(p[0], p[1])],
                  color: color.withValues(alpha: active ? 0.16 : 0.05),
                  borderColor: color.withValues(alpha: active ? 0.95 : 0.45),
                  borderStrokeWidth: active ? 3 : 1.5,
                  label: z.name,
                  labelStyle: TextStyle(
                    color: color.withValues(alpha: active ? 1 : 0.6),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
                  ),
                );
              }(),
        ];

        // ӨНӨӨДРИЙН ажил дээр томроно — бүх бүсэд багтаавал дугаар уншигдахгүй.
        if (!_fitted && allPoints.isNotEmpty) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fit(allPoints, 46);
          });
        }

        final map = ClipRRect(
          borderRadius: BorderRadius.circular(_expanded ? 0 : 12),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: const MapOptions(initialCenter: _ubCenter, initialZoom: 12),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    // ⚠ Зарим утасны сүлжээнээс tile.openstreetmap.org хүрэгдэхгүй —
                    //   web дээрх шиг Герман mirror нөөц.
                    fallbackUrl: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                    userAgentPackageName: 'mn.akifoods.akifoods_app',
                  ),
                  PolygonLayer(polygons: polygons),
                  MarkerLayer(markers: markers),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
                ],
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    tooltip: _expanded ? 'Жижигрүүлэх' : 'Дэлгэцээр харах',
                    icon: Icon(_expanded ? Icons.fullscreen_exit : Icons.fullscreen),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ),
              ),
            ],
          ),
        );

        if (_expanded) return map;

        return RefreshIndicator(
          onRefresh: () async {
            // Бүс өмнө нь ачаалж чадаагүй бол дахин оролдоно.
            await Future.wait([c.loadOrders(), if (c.zones.isEmpty || _message != null) _load()]);
            _fitted = false;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              MessageBanner(_message, onClose: () => setState(() => _message = null)),
              if (missing > 0)
                MessageBanner(AppMessage.warning('$missing зогсоол зурагт алга (онлайн эсвэл байршил тэмдэглээгүй).')),
              SizedBox(height: 360, child: _loading && c.zones.isEmpty ? const LoadingState('Ачаалж байна…') : map),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Өнөөдөр бэлдэх',
                subtitle: 'Дугаар нь түгээлтийн хуудасны дугаартай ижил. Бүс дээр дарж томруулна.',
                child: zones.isEmpty
                    ? const EmptyState('Хүлээгдэж буй захиалга алга байна.')
                    : Column(
                        children: [
                          for (final z in zones.values)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(color: z.color, shape: BoxShape.circle),
                              ),
                              title: Text(z.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${z.stores} дэлгүүр · ${z.orders} захиалга'),
                              trailing: Text(
                                z.first == z.last ? '№${z.first}' : '№${z.first}–${z.last}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              // Бүсгүй (онлайн) зогсоол зурагт байхгүй — дарахад юу ч болохгүй нь зөв.
                              onTap: z.points.isEmpty ? null : () => _fit(z.points, 70),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _fit(List<LatLng> points, double padding) {
    try {
      if (points.length == 1) {
        _map.move(points.first, 15);
      } else {
        _map.fitCamera(CameraFit.coordinates(coordinates: points, padding: EdgeInsets.all(padding), maxZoom: 15));
      }
    } catch (_) {
      // Зураг хараахан зурагдаагүй — дараагийн удаад.
    }
  }

  void _showStop(int no, SheetStop stop, String zoneName) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('№$no · ${stop.name} · Бүс: $zoneName · ${stop.orderCount} захиалга')));
  }
}
