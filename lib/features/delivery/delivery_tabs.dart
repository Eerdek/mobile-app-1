import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/api_client.dart';
import '../../core/date_range.dart';
import '../../core/excel_export.dart';
import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/map_widgets.dart';
import '../../core/ui.dart';
import '../../printing/order_receipt.dart';
import '../factory/factory_logic.dart' show zoneTone, zoneKey;
import '../factory/factory_models.dart' show ZoneRow;
import '../factory/factory_widgets.dart';
import 'delivery_controller.dart';
import 'delivery_logic.dart';

Widget statusTag(String status) {
  final label = statusLabels[status] ?? status;
  return switch (status) {
    'delivered' => Tag(label, color: AppColors.success, background: AppColors.successSoft),
    'returned' => Tag(label, color: AppColors.danger, background: AppColors.dangerSoft),
    _ => Tag.warning(label),
  };
}

// ════════════════════════════════════════════════════════════════════════
// Хянах самбар
// ════════════════════════════════════════════════════════════════════════
class DeliveryDashboardTab extends StatefulWidget {
  final DeliveryController controller;
  final VoidCallback onOpenReport;
  const DeliveryDashboardTab({super.key, required this.controller, required this.onOpenReport});

  @override
  State<DeliveryDashboardTab> createState() => _DeliveryDashboardTabState();
}

class _DeliveryDashboardTabState extends State<DeliveryDashboardTab> {
  DateRange _range = DateRange.preset(RangePreset.today);

  DeliveryController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final isToday = _range.isToday;
        final delivered = deliveredIn(c.history, _range);
        final totals = MoneyTotals.of(delivered);
        final returned = c.history.where((o) => o.status == 'returned' && _range.contains(o.when)).length;
        final sub = isToday ? 'өнөөдөр' : 'сонгосон хугацаанд';

        // «Өнөөдрийн явц» — хүрээнээс хамааралгүй (оноогдсон ажил = одоогийн төлөв).
        final todayDelivered = deliveredIn(c.history, DateRange.preset(RangePreset.today));
        final today = MoneyTotals.of(todayDelivered);
        final assignedTotal = c.assigned.fold<num>(0, (s, o) => s + o.totalAmount);
        final stops = todayDelivered.length + c.assigned.length;
        final pct = stops == 0 ? 0.0 : todayDelivered.length / stops;
        final spark = last7DeliveredAmounts(c.history);

        final recent = c.history.where((o) => _range.contains(o.when)).toList()
          ..sort((a, b) => '${b.when}'.compareTo('${a.when}'));

        return RefreshIndicator(
          onRefresh: c.loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              MessageBanner(c.message, onClose: () => c.setMessage(null)),
              DateRangeBar(
                value: _range,
                onChanged: (r) {
                  setState(() => _range = r);
                  c.ensureHistoryCovers(r);
                },
              ),
              const SizedBox(height: 12),
              _Hero(
                label: isToday ? 'Өнөөдөр хүргэсэн дүн' : 'Хүргэсэн дүн',
                value: formatMoney(totals.total),
                caption: isToday ? '${totals.count} хүргэлт гүйцэтгэсэн' : '${totals.count} хүргэлт · ${_range.label}',
                spark: spark,
              ),
              const SizedBox(height: 8),
              _Grid(children: [
                KpiTile(label: 'Хүлээгдэж буй', value: '${c.assigned.length}', caption: 'оноогдсон захиалга'),
                KpiTile(label: 'Хүргэсэн', value: '${totals.count}', caption: sub),
                KpiTile(label: 'Зээлээр', value: formatMoney(totals.credit), caption: isToday ? 'өнөөдрийн зээл' : 'хугацааны зээл'),
                KpiTile(label: 'Буцаагдсан', value: '$returned', caption: sub),
              ]),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Өнөөдрийн явц',
                subtitle: 'Хүргэлтийн гүйцэтгэл ба дүн',
                actions: [Text('${(pct * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))],
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: pct, minHeight: 8, color: AppColors.success, backgroundColor: AppColors.border),
                  ),
                  const SizedBox(height: 8),
                  AccRow('Хүргэсэн', Text('${todayDelivered.length}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  AccRow('Үлдсэн', Text('${c.assigned.length}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  AccRow('Хүргэсэн дүн', Text(formatMoney(today.total), style: const TextStyle(fontWeight: FontWeight.w700))),
                  AccRow('Үлдсэн дүн', Text(formatMoney(assignedTotal), style: const TextStyle(fontWeight: FontWeight.w700))),
                  AccRow('Өнөөдрийн зээл', Text(formatMoney(today.credit), style: const TextStyle(fontWeight: FontWeight.w700))),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenReport,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Тайлан ба бэлэн мөнгө тулгах'),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Сүүлийн хүргэлтүүд',
                subtitle: 'Хамгийн сүүлд гүйцэтгэсэн үйл ажиллагаа',
                child: recent.isEmpty
                    ? const EmptyState('Энэ хугацаанд хүргэлт хийгдээгүй байна.')
                    : Column(children: [
                        for (final o in recent.take(5))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(o.storeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${formatDateTime(o.when)}${o.status == 'delivered' ? ' · ${paymentParts(o).map((p) => paymentLabels[p.$1] ?? p.$1).join(', ')}' : ''}',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [Text(formatMoney(o.payable), style: const TextStyle(fontWeight: FontWeight.w700)), statusTag(o.status)],
                            ),
                            onTap: () => OrderReceiptScreen.open(context, c.api, o.id),
                          ),
                      ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 4 : 2;
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final w in children) SizedBox(width: width, child: w)]);
      });
}

class _Hero extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final List<num> spark;
  const _Hero({required this.label, required this.value, required this.caption, required this.spark});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Color(0xCCFFFFFF))),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              Text(caption, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
            ]),
          ),
          SizedBox(width: 100, height: 44, child: CustomPaint(painter: _SparkPainter(spark))),
        ]),
      );
}

class _SparkPainter extends CustomPainter {
  final List<num> values;
  const _SparkPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || values.every((v) => v == 0)) return;
    final maxV = values.fold<num>(1, (m, v) => math.max(m, v));
    final step = values.length > 1 ? size.width / (values.length - 1) : 0.0;
    final pts = [
      for (var i = 0; i < values.length; i++) Offset(i * step, size.height - values[i] / maxV * (size.height - 6) - 3),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = const Color(0x29FFFFFF));
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xEBFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values;
}

// ════════════════════════════════════════════════════════════════════════
// Маршрут
// ════════════════════════════════════════════════════════════════════════
class DeliveryRouteTab extends StatefulWidget {
  final DeliveryController controller;
  const DeliveryRouteTab({super.key, required this.controller});

  @override
  State<DeliveryRouteTab> createState() => _DeliveryRouteTabState();
}

class _DeliveryRouteTabState extends State<DeliveryRouteTab> {
  final MapController _map = MapController();
  List<ZoneRow> _zones = const [];
  bool _expanded = false;
  String _fittedFor = '';

  DeliveryController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.refreshCoords();
    _loadZones();
  }

  // ⚠ Нэг л удаа татна; уналт нь маршрутыг УНАГАХГҮЙ — зүгээр л дэвсгэргүй.
  Future<void> _loadZones() async {
    try {
      final res = await c.api.get('/zones');
      if (!mounted) return;
      setState(() => _zones = jsonList(res).map(ZoneRow.fromJson).toList());
    } catch (_) {}
  }

  ZoneRow? _zoneOf(double lat, double lng) {
    for (final z in _zones) {
      if (z.polygon.length >= 3 && pointInPolygon(lat, lng, z.polygon)) return z;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final raw = c.assigned.where((o) => o.address != null || o.location != null).toList();
        final stops = optimizeRoute(raw, c.myCoords);
        final me = c.myCoords;

        final markers = <Marker>[];
        final path = <LatLng>[];
        final active = <String>{};
        if (me != null) {
          path.add(LatLng(me.$1, me.$2));
          markers.add(Marker(
            point: LatLng(me.$1, me.$2),
            width: 22,
            height: 22,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ));
        }
        for (final (i, o) in stops.indexed) {
          final ll = o.coords;
          if (ll == null) continue;
          // Pin бүсийнхээ өнгөтэй — захиалгад бүсийн нэр дагадаггүй тул координатаар ОЛНО.
          final zone = _zoneOf(ll.$1, ll.$2);
          final color = zone == null ? const Color(0xFF64748B) : Color(zoneTone(zone.name, zone.color));
          if (zone != null) active.add(zoneKey(zone.name));
          final point = LatLng(ll.$1, ll.$2);
          path.add(point);
          markers.add(Marker(
            point: point,
            width: 28,
            height: 36,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('№${i + 1} · ${o.storeName}${zone != null ? ' · Бүс: ${zone.name}' : ''}'),
                )),
              child: NumberPin(color: color, number: i + 1),
            ),
          ));
        }
        final polygons = [
          for (final z in _zones)
            if (z.polygon.length >= 3)
              () {
                final color = Color(zoneTone(z.name, z.color));
                final on = active.contains(zoneKey(z.name));
                return Polygon(
                  points: [for (final p in z.polygon) LatLng(p[0], p[1])],
                  color: color.withValues(alpha: on ? 0.14 : 0.05),
                  borderColor: color.withValues(alpha: on ? 0.95 : 0.45),
                  borderStrokeWidth: on ? 3 : 1.5,
                  label: z.name,
                  labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
                );
              }(),
        ];

        final fitKey = '${path.length}:${me != null}';
        if (path.isNotEmpty && fitKey != _fittedFor) {
          _fittedFor = fitKey;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              if (path.length == 1) {
                _map.move(path.first, 15);
              } else {
                _map.fitCamera(CameraFit.coordinates(coordinates: path, padding: const EdgeInsets.all(46), maxZoom: 15));
              }
            } catch (_) {}
          });
        }

        final map = ClipRRect(
          borderRadius: BorderRadius.circular(_expanded ? 0 : 12),
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: const MapOptions(initialCenter: LatLng(47.9185, 106.9176), initialZoom: 12),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  fallbackUrl: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                  userAgentPackageName: 'mn.akifoods.akifoods_app',
                ),
                PolygonLayer(polygons: polygons),
                if (path.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: path,
                      color: const Color(0xBF137A52),
                      strokeWidth: 3,
                      pattern: StrokePattern.dashed(segments: const [7, 7]),
                    ),
                  ]),
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
          ]),
        );
        if (_expanded) return map;

        return RefreshIndicator(
          onRefresh: () async {
            await c.loadAll();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              SizedBox(height: 340, child: map),
              const SizedBox(height: 8),
              const Text('Таны байршлаас ойроос хол руу — хамгийн оновчтой дараалал',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              if (stops.isEmpty) const EmptyState('Маршрутад оруулах хүргэлт алга.'),
              for (final (i, o) in stops.indexed)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.brand,
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    title: Text(o.storeName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([o.address ?? '—', if (o.isOnline) 'Онлайн · Төлсөн'].join(' · ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (o.phone != null)
                        IconButton(tooltip: 'Залгах', icon: const Icon(Icons.phone_outlined), onPressed: () => callPhone(o.phone)),
                      if (directionsUri(o.location, o.address) != null)
                        IconButton(
                          tooltip: 'Чиглүүлэх',
                          icon: const Icon(Icons.navigation_outlined, color: AppColors.brand),
                          onPressed: () => openDirections(o.location, o.address),
                        ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Ачаа хүлээн авах
// ════════════════════════════════════════════════════════════════════════
// ⚠ «Бүгдийг тоолсон» бөөний товч ЗОРИУД БАЙХГҮЙ — түгээгч ачааг нэг бүрчлэн
//   тоолдог; тэгэхгүй бол дэлгэцийн ГАНЦ үүрэг (юу дутаж байна) утгаа алдана.
class DeliveryReceiveTab extends StatefulWidget {
  final DeliveryController controller;
  const DeliveryReceiveTab({super.key, required this.controller});

  @override
  State<DeliveryReceiveTab> createState() => _DeliveryReceiveTabState();
}

class _DeliveryReceiveTabState extends State<DeliveryReceiveTab> {
  final Set<String> _open = {};

  DeliveryController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.loadRecvCounts();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final products = buildRecvProducts(c.assigned);
        var need = 0, got = 0;
        for (final p in products) {
          need += p.needQty;
          got += math.min(p.needQty, math.max(0, c.recvCounts[p.key] ?? 0));
        }
        final short = math.max(0, need - got);

        final groups = <String, List<RecvProduct>>{};
        for (final p in products) {
          groups.putIfAbsent((p.categoryName ?? '').trim().isEmpty ? 'Ангилалгүй' : p.categoryName!.trim(), () => []).add(p);
        }
        final groupNames = groups.keys.toList()
          ..sort((a, b) {
            if ((a == 'Ангилалгүй') != (b == 'Ангилалгүй')) return a == 'Ангилалгүй' ? 1 : -1;
            return mnCompare(a, b);
          });

        return RefreshIndicator(
          onRefresh: c.loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              const Text('Тоолсон тоогоо оруулна — дутвал аль дэлгүүрт хэдээр дутахыг доор нь нэрлэнэ',
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              _Grid(children: [
                KpiTile(label: 'Нэр төрөл', value: formatQty(products.length)),
                KpiTile(label: 'Ачаанд байх ёстой', value: formatQty(need)),
                KpiTile(label: 'Тоолсон', value: formatQty(got), accent: AppColors.success),
                // ⚠ «Дутуу 0» нь анхааруулга БИШ — өнгө нь зөвхөн бодит дутагдалд.
                KpiTile(label: 'Дутуу', value: formatQty(short), accent: short > 0 ? AppColors.danger : null),
              ]),
              const SizedBox(height: 12),
              if (products.isEmpty)
                const EmptyState('Үйлдвэрээс гарсан ачаа алга — хүлээн авах бараа байхгүй.')
              else
                for (final name in groupNames) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                    child: Text(
                      '${name.toUpperCase()} · ${groups[name]!.length} нэр · ${formatQty(groups[name]!.fold<int>(0, (s, p) => s + p.needQty))}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.muted),
                    ),
                  ),
                  for (final p in groups[name]!) _recvTile(p),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _recvTile(RecvProduct p) {
    final done = math.min(p.needQty, math.max(0, c.recvCounts[p.key] ?? 0));
    final parts = allocateRecv(p, done);
    final shortTotal = parts.fold<int>(0, (s, a) => s + a.short);
    final tint = done >= p.needQty ? const Color(0xFFF3FAF6) : done > 0 ? const Color(0xFFFFFBF0) : null;
    return ExpandTile(
      key: ValueKey('recv:${p.key}'),
      open: _open.contains(p.key),
      onToggle: (o) => setState(() => o ? _open.add(p.key) : _open.remove(p.key)),
      tint: tint,
      title: Text(p.name),
      subtitle: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${p.productCode != null ? 'Код ${p.productCode} · ' : ''}${p.stores.length} дэлгүүр',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        if (shortTotal > 0)
          Tag('${formatQty(shortTotal)} дутуу', color: AppColors.danger, background: AppColors.dangerSoft),
      ]),
      trailing: PrepControl(
        key: ValueKey('recvctl:${p.key}'),
        done: done,
        need: p.needQty,
        ofLabel: Text('/ ${formatQty(p.needQty)} ${p.unitLabel}'),
        semanticName: p.name,
        onCommit: (v) => c.setRecvCount(p.key, v),
        // Дүүрсэн бол АРИЛГАНА, эс бөгөөс ДҮҮРГЭНЭ.
        onToggle: () => c.setRecvCount(p.key, done >= p.needQty ? 0 : p.needQty),
      ),
      children: [
        for (final a in parts)
          AccRow(
            [
              if (a.store.storeCode != null) '${a.store.storeCode}',
              a.store.name,
              if (a.store.online) 'Онлайн',
              if (a.store.zone != null) a.store.zone!,
            ].join(' · '),
            Text.rich(TextSpan(children: [
              if (a.short > 0)
                TextSpan(
                  text: '${formatQty(a.short)} ${p.unitLabel} дутуу  ',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                ),
              TextSpan(text: '${formatQty(a.store.qty)} ${p.unitLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ])),
            warn: a.short > 0,
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Тайлан — бэлэн мөнгө тулгах (blind count)
// ════════════════════════════════════════════════════════════════════════
// ⚠ АНТИ-SCAM: өнөөдрийн тушаах бэлэн дүнг УРЬДЧИЛЖ харуулахгүй. Түгээгч
//   бэлнээ өөрөө тоолж оруулаад «Шалгах» дарна. БУРУУ бол яг дүн/зөрүүг
//   ХАРУУЛАХГҮЙ — зөвхөн «дахин тоол». ТААРСАН үед л ил болно. Excel ч
//   тулгаагүй байхад татагдахгүй (файлаас дүн ил гарахаас сэргийлнэ).
class DeliveryReportScreen extends StatefulWidget {
  final DeliveryController controller;
  const DeliveryReportScreen({super.key, required this.controller});

  @override
  State<DeliveryReportScreen> createState() => _DeliveryReportScreenState();
}

class _DeliveryReportScreenState extends State<DeliveryReportScreen> {
  DateRange _range = DateRange.preset(RangePreset.today);
  bool _revealed = false;
  bool? _lastWrong;
  final _counted = TextEditingController();

  DeliveryController get c => widget.controller;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  bool get _masked => _range.isToday && !_revealed;

  void _setRange(DateRange r) {
    setState(() {
      _range = r;
      // Хүрээ солиход тушаах дүнг дахин нууна.
      _revealed = false;
      _lastWrong = null;
      _counted.clear();
    });
    c.ensureHistoryCovers(r);
  }

  void _check(num due) {
    final counted = num.tryParse(_counted.text.trim()) ?? 0;
    final diff = ((counted - due) * 100).round() / 100;
    setState(() {
      if (diff.abs() < 0.5) {
        _revealed = true;
        _lastWrong = false;
      } else {
        _lastWrong = true;
      }
    });
  }

  Future<void> _export(List<DeliveryOrder> orders) async {
    if (_masked) {
      c.setMessage(const AppMessage.warning('Эхлээд бэлэн мөнгөө тулгана уу.'));
      return;
    }
    if (orders.isEmpty) {
      c.setMessage(const AppMessage.error('Татах өгөгдөл алга.'));
      return;
    }
    try {
      await shareExcel(fileBaseName: 'Тооцооны задаргаа ${_range.label}', sheetName: 'Тооцооны задаргаа', rows: reportSheetRows(orders));
    } catch (e) {
      c.setMessage(AppMessage.error('Excel үүсгэхэд алдаа гарлаа: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Тайлан')),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final orders = deliveredIn(c.history, _range);
          final t = MoneyTotals.of(orders);
          String mask(num v) => _masked ? '•••₮' : formatMoney(v);
          String money(num v) => v > 0 ? formatMoney(v) : '—';
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              MessageBanner(c.message, onClose: () => c.setMessage(null)),
              DateRangeBar(value: _range, onChanged: _setRange),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_range.isToday ? 'Тушаах бэлэн мөнгө' : _range.label, style: const TextStyle(color: Color(0xCCFFFFFF))),
                  Text(
                    _range.isToday ? mask(t.cash) : formatMoney(t.total),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  Text(_range.isToday ? _range.label : '${orders.length} захиалга хүргэсэн',
                      style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
                ]),
              ),
              if (_range.isToday) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Бэлэн мөнгө тулгах',
                  subtitle: 'Гарт байгаа бэлнээ тоолоод Шалгах товч дарна уу',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _counted,
                          enabled: !_revealed,
                          // ⚠ ЗӨВХӨН цифр — «12e312» мэт утга худал «Таарлаа» өгдөг байсан.
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
                          decoration: const InputDecoration(labelText: 'Тоолсон бэлэн мөнгө', suffixText: '₮'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _revealed ? null : () => _check(t.cash),
                        child: Text(_revealed ? 'Баталгаажсан' : _lastWrong == true ? 'Дахин шалгах' : 'Шалгах'),
                      ),
                    ]),
                    if (_lastWrong == true) ...[
                      const SizedBox(height: 8),
                      const MessageBanner(AppMessage.warning('Дахин тоолж, зөв дүнг оруулна уу.')),
                    ],
                    if (_revealed) ...[
                      const SizedBox(height: 8),
                      MessageBanner(AppMessage.success('Таарлаа — тушаах: ${formatMoney(t.cash)}')),
                    ],
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              SectionCard(
                title: 'Тооцооны задаргаа',
                subtitle: 'Мөр дээр дарж баримтыг харна',
                actions: [IconButton(tooltip: 'Excel', icon: const Icon(Icons.download_outlined), onPressed: () => _export(orders))],
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (orders.isEmpty) const EmptyState('Энэ хугацаанд хүргэсэн захиалга алга.'),
                  for (final o in orders)
                    InkWell(
                      onTap: () => OrderReceiptScreen.open(context, c.api, o.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          SizedBox(
                            width: 52,
                            child: Text(_range.isSingleDay ? hhmm(o.when) : formatDateTime(o.when).substring(5),
                                style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o.storeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                'Данс ${money(o.transferAmount)} · Бэлэн ${_masked ? '•••₮' : money(o.cashAmount)} · Зээл ${money(o.creditAmount)}',
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ]),
                          ),
                          // ⚠ Нийт ч нуугдана — эс бөгөөс бэлэн дүн Нийтээс сэргээгдэнэ.
                          Text(mask(o.payable), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  const Divider(),
                  AccRow('Данс', Text(formatMoney(t.transfer), style: const TextStyle(fontWeight: FontWeight.w700))),
                  AccRow('Бэлэн', Text(mask(t.cash), style: const TextStyle(fontWeight: FontWeight.w700))),
                  AccRow('Зээл', Text(formatMoney(t.credit), style: const TextStyle(fontWeight: FontWeight.w700))),
                  AccRow('Нийт дүн', Text(mask(t.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Хүргэлтийн түүх
// ════════════════════════════════════════════════════════════════════════
class DeliveryHistoryTab extends StatefulWidget {
  final DeliveryController controller;
  final String courierName;
  const DeliveryHistoryTab({super.key, required this.controller, required this.courierName});

  @override
  State<DeliveryHistoryTab> createState() => _DeliveryHistoryTabState();
}

class _DeliveryHistoryTabState extends State<DeliveryHistoryTab> {
  DateRange _range = DateRange.preset(RangePreset.today);
  String _status = '';
  String _seller = '';
  final Set<String> _open = {};

  DeliveryController get c => widget.controller;

  Future<void> _export(List<DeliveryOrder> rows) async {
    if (rows.isEmpty) {
      c.setMessage(const AppMessage.error('Татах өгөгдөл алга.'));
      return;
    }
    try {
      await shareExcel(
        fileBaseName: 'Хүргэлтийн түүх ${_range.label}',
        sheetName: 'Хүргэлтийн түүх',
        rows: historySheetRows(rows, widget.courierName),
      );
    } catch (e) {
      c.setMessage(AppMessage.error('Excel үүсгэхэд алдаа гарлаа: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // Борлуулагчийн сонголт нь ХҮРЭЭ + ТӨЛӨВӨӨР шүүсэн мөрөөс (өөрийгөө оролцуулахгүй —
        // эс бөгөөс нэгийг сонгомогц бусад нь алга болж буцаж солих аргагүй болно).
        final base = filterHistory(c.history, range: _range, status: _status);
        final names = <String>{for (final o in base) if (o.sellerName != null) o.sellerName!}.toList()..sort(mnCompare);
        final hasNone = base.any((o) => o.sellerName == null);
        final validSeller = _seller.isEmpty ||
            (_seller == sellerNone ? hasNone : names.contains(_seller.length > 2 ? _seller.substring(2) : ''));
        final seller = validSeller ? _seller : '';
        final rows = filterHistory(c.history, range: _range, status: _status, seller: seller);

        return RefreshIndicator(
          onRefresh: c.loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              MessageBanner(c.message, onClose: () => c.setMessage(null)),
              DateRangeBar(
                value: _range,
                onChanged: (r) {
                  setState(() => _range = r);
                  c.ensureHistoryCovers(r);
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Төлөв'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Бүх төлөв')),
                      DropdownMenuItem(value: 'delivered', child: Text('Хүргэсэн')),
                      DropdownMenuItem(value: 'returned', child: Text('Буцаагдсан')),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('seller:$seller:${names.length}:$hasNone'),
                    initialValue: seller,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Борлуулагч'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Бүх борлуулагч')),
                      for (final n in names) DropdownMenuItem(value: 'n:$n', child: Text(n, overflow: TextOverflow.ellipsis)),
                      if (hasNone) const DropdownMenuItem(value: sellerNone, child: Text('Борлуулагчгүй')),
                    ],
                    onChanged: (v) => setState(() => _seller = v ?? ''),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Хүргэлтийн түүх',
                subtitle: 'Мөр дээр дарж дэлгүүрийн мэдээлэл, баримтыг харна',
                actions: [IconButton(tooltip: 'Excel', icon: const Icon(Icons.download_outlined), onPressed: () => _export(rows))],
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (rows.isEmpty) EmptyState(c.history.isEmpty ? 'Хүргэлтийн түүх алга.' : 'Шүүлтэд тохирох хүргэлт алга.'),
                  for (final o in rows)
                    ExpandTile(
                      key: ValueKey('h:${o.id}'),
                      open: _open.contains(o.id),
                      onToggle: (v) => setState(() => v ? _open.add(o.id) : _open.remove(o.id)),
                      title: Text(o.storeName),
                      subtitle: Text('${formatDateTime(o.when)} · ${formatMoney(o.payable)}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                      trailing: statusTag(o.status),
                      children: [
                        AccRow('Утас', Text(o.phone ?? '-')),
                        AccRow('Хаяг', Flexible(child: Text(o.address ?? '-', textAlign: TextAlign.right))),
                        AccRow('Борлуулагч', Text(o.sellerName == null ? '-' : '${o.sellerName}${o.sellerPhone != null ? ' · ${o.sellerPhone}' : ''}')),
                        if (o.status == 'delivered')
                          for (final p in paymentParts(o))
                            AccRow(paymentLabels[p.$1] ?? p.$1, Text(formatMoney(p.$2), style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (o.discountAmount > 0) ...[
                          AccRow('Барааны дүн', Text(formatMoney(o.totalAmount))),
                          AccRow('Урамшуулал', Text('−${formatMoney(o.discountAmount)}')),
                        ],
                        AccRow('Нийт дүн', Text(formatMoney(o.payable), style: const TextStyle(fontWeight: FontWeight.w800))),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: () => OrderReceiptScreen.open(context, c.api, o.id),
                            child: const Text('Баримт харах'),
                          ),
                        ),
                      ],
                    ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Тест болон гаднаас API алдааг уншихад.
String apiErrorText(Object e, String fallback) => e is ApiException ? e.message : fallback;
