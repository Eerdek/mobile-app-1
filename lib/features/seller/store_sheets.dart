import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/links.dart';
import '../../core/ui.dart';
import '../factory/factory_logic.dart' show zoneTone;
import 'seller_controller.dart';
import 'seller_logic.dart';
import 'seller_widgets.dart';
import 'store_picker.dart' show StoreImage;

const _ubCenter = LatLng(47.9185, 106.9176);

// ── Камерын зураг ───────────────────────────────────────────────────────────
/// Камераар ДӨНГӨЖ дарсан зураг ({imageData: data URL, imageName}).
/// ⚠ Эх сурвалж нь ЗӨВХӨН камер — галерейн хуучин зургаар өрөлт
///   «баталгаажуулах» боломжгүй (web дээр lastModified-оор шалгадаг байсан).
/// 1600px хүртэл багасгаж JPEG q≈82 — web-ийн compressImage-тэй ижил.
Future<Json?> captureCameraImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 82,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final name = file.name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
  return {
    'imageData': 'data:image/jpeg;base64,${base64Encode(bytes)}',
    'imageName': '${name.isEmpty ? 'photo' : name}.jpg',
  };
}

Widget dataUrlImage(String dataUrl, {double size = 96}) {
  final comma = dataUrl.indexOf(',');
  final bytes = base64Decode(comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl);
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
  );
}

List<List<double>> _polygonOf(Json zone) => (zone['polygon'] is List ? zone['polygon'] as List : const [])
    .whereType<List>()
    .where((p) => p.length == 2)
    .map((p) => [toNum(p[0]).toDouble(), toNum(p[1]).toDouble()])
    .toList();

TileLayer _tiles() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  fallbackUrl: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
  userAgentPackageName: 'mn.akifoods.akifoods_app',
);

// ── Бүсийн газрын зураг ─────────────────────────────────────────────────────
/// Өөрийн бүсийн полигон + дэлгүүрүүд (зөвхөн харах). Senior бүх бүсийг.
/// Өнөөдрийн маршрут ногоон, бусад саарал, өөрийн байршил хөх цэг.
// Бүс + GPS (4с хүртэл) хүлээх зуур дахин дарвал олон дэлгэц давхарлахгүй.
bool _zoneMapOpening = false;

Future<void> openZoneMap(BuildContext context, SellerController c) async {
  if (_zoneMapOpening) return;
  _zoneMapOpening = true;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Газрын зураг ачаалж байна…'), duration: Duration(seconds: 2)));
  try {
    await _openZoneMap(context, c);
  } finally {
    _zoneMapOpening = false;
  }
}

Future<void> _openZoneMap(BuildContext context, SellerController c) async {
  List<Json> zones;
  try {
    zones = jsonList(await c.api.get('/zones'));
  } catch (e) {
    c.setMessage(AppMessage.error(SellerController.errorText(e, 'Бүсийн мэдээлэл ачаалахад алдаа гарлаа.')));
    return;
  }
  // GPS-ийг дээд тал нь 4с хүлээнэ — удаашрахад зургийг хүлээлгэхгүй.
  final me = await GeoService.instance.getCoords().timeout(const Duration(seconds: 4), onTimeout: () => null);
  // user.zone байхгүй (хуучин login) бол өөрийн дэлгүүрүүдийн бүсээс.
  String? myZone = c.user.zone;
  if (myZone == null && !c.isSenior) {
    for (final s in c.stores) {
      if (str(s['zone']) != null) {
        myZone = str(s['zone']);
        break;
      }
    }
  }
  final visible = c.isSenior ? zones : zones.where((z) => z['name'] == myZone).toList();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _ZoneMapScreen(
        controller: c,
        zones: visible,
        label: myZone ?? (c.isSenior ? 'Бүх бүс' : 'Бүс оноогоогүй'),
        me: me,
      ),
    ),
  );
}

class _ZoneMapScreen extends StatelessWidget {
  final SellerController controller;
  final List<Json> zones;
  final String label;
  final Coords? me;
  const _ZoneMapScreen({required this.controller, required this.zones, required this.label, required this.me});

  @override
  Widget build(BuildContext context) {
    final today = <(Json, LatLng)>[];
    final other = <(Json, LatLng)>[];
    final bounds = <LatLng>[];
    for (final s in controller.stores) {
      final ll = parseLatLng(str(s['location']));
      if (ll == null) continue;
      final p = LatLng(ll.$1, ll.$2);
      bounds.add(p);
      (isTodayStore(s) ? today : other).add((s, p));
    }
    for (final z in zones) {
      for (final p in _polygonOf(z)) {
        bounds.add(LatLng(p[0], p[1]));
      }
    }
    // Эцсийн харагдац: байршилтай → би + хамгийн ойрын (өнөөдрийнхийг түрүүлж);
    // байршилгүй → өнөөдрийн дэлгүүрүүд; тэр ч үгүй бол бүгд.
    List<LatLng> fitPoints = bounds;
    final m = me;
    if (m != null) {
      final mp = LatLng(m.lat, m.lng);
      final candidates = today.isNotEmpty ? today : other;
      if (candidates.isNotEmpty) {
        double d(LatLng p) =>
            (p.latitude - mp.latitude) * (p.latitude - mp.latitude) +
            (p.longitude - mp.longitude) * (p.longitude - mp.longitude);
        final nearest = candidates.reduce((a, b) => d(a.$2) < d(b.$2) ? a : b);
        fitPoints = [mp, nearest.$2];
      } else {
        fitPoints = [mp];
      }
    } else if (today.isNotEmpty) {
      fitPoints = today.map((e) => e.$2).toList();
    }

    void showStore(Json s, String status) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${s['name'] ?? ''}',
                  style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (str(s['address']) != null) Text('${s['address']}', style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 4),
                Text(status, style: const TextStyle(fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    Navigator.of(context).pop();
                    controller.selectStore('${s['id']}');
                  },
                  child: const Text('Дэлгэрэнгүй'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Marker pin(Json s, LatLng p, Color color, String status, {double size = 30}) => Marker(
      point: p,
      width: size,
      height: size,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => showStore(s, status),
        child: Icon(
          Icons.location_on,
          color: color,
          size: size,
          shadows: const [Shadow(color: Colors.white, blurRadius: 4)],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Бүсийн газрын зураг'),
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _ubCenter,
                initialZoom: 12,
                initialCameraFit: fitPoints.isEmpty
                    ? null
                    : fitPoints.length == 1
                    ? CameraFit.coordinates(
                        coordinates: [fitPoints.first, fitPoints.first],
                        maxZoom: 15,
                        padding: const EdgeInsets.all(48),
                      )
                    : CameraFit.coordinates(coordinates: fitPoints, maxZoom: 16, padding: const EdgeInsets.all(48)),
              ),
              children: [
                _tiles(),
                PolygonLayer(
                  polygons: [
                    for (final z in zones)
                      if (_polygonOf(z).length >= 3)
                        Polygon(
                          points: [for (final p in _polygonOf(z)) LatLng(p[0], p[1])],
                          color: Color(zoneTone('${z['name']}', str(z['color']))).withValues(alpha: 0.06),
                          borderColor: Color(zoneTone('${z['name']}', str(z['color']))).withValues(alpha: 0.9),
                          borderStrokeWidth: 2.5,
                          label: '${z['name']}',
                          labelStyle: TextStyle(
                            color: Color(zoneTone('${z['name']}', str(z['color']))),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final (s, p) in other)
                      pin(s, p, const Color(0xFF94A3B8), 'Өнөөдрийн хуваарьт ороогүй', size: 24),
                    for (final (s, p) in today) pin(s, p, const Color(0xFF16A36A), 'Өнөөдрийн маршрут', size: 34),
                    if (m != null)
                      Marker(
                        point: LatLng(m.lat, m.lng),
                        width: 18,
                        height: 18,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
              ],
            ),
          ),
          const SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _Legend(Color(0xFF16A36A), 'Өнөөдрийн маршрут'),
                  _Legend(Color(0xFF94A3B8), 'Хуваарьт ороогүй'),
                  _Legend(Color(0xFF2563EB), 'Таны байршил'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend(this.color, this.text);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
    ],
  );
}

// ── Регистрийн хайлт (web-ийн register-lookup.js) ───────────────────────────
// ⚠ Хуудасны кэш — ижил регистр хоёр дахь удаа асуухгүй.
final Map<String, Json> _registerCache = {};

/// Олдсон албан ёсны нэр (хадгалахад registerName болж явна) эсвэл null.
String? registerNameFor(String raw) {
  final hit = _registerCache[sanitizeRegister(raw)];
  return hit != null && hit['found'] == true && str(hit['name']) != null ? str(hit['name']) : null;
}

// ── Шинэ дэлгүүр / засвар ───────────────────────────────────────────────────
/// ⚠ НЭГ маягт, ХОЁР горим — тусдаа бол регистрийн хайлт, шалгуурууд хоёр хувь
///   болж нэг нь хоцорно. [edit] өгвөл засварын горим.
Future<void> openStoreForm(BuildContext context, SellerController c, {Json? edit}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _StoreFormScreen(controller: c, edit: edit),
  ),
);

class _StoreFormScreen extends StatefulWidget {
  final SellerController controller;
  final Json? edit;
  const _StoreFormScreen({required this.controller, this.edit});

  @override
  State<_StoreFormScreen> createState() => _StoreFormScreenState();
}

class _StoreFormScreenState extends State<_StoreFormScreen> {
  late final _name = TextEditingController(text: str(widget.edit?['name']) ?? '');
  late final _register = TextEditingController(text: str(widget.edit?['register']) ?? '');
  late final _contact = TextEditingController(text: str(widget.edit?['contactName']) ?? '');
  late final _phone = TextEditingController(text: str(widget.edit?['phone']) ?? '');
  late final _address = TextEditingController(text: str(widget.edit?['address']) ?? '');
  late final _note = TextEditingController(text: str(widget.edit?['note']) ?? '');
  late String _type = str(widget.edit?['storeType']) ?? '';
  Json? _image;
  String? _hint;
  Color _hintColor = AppColors.muted;
  String? _autoFilledName;
  Timer? _debounce;
  bool _busy = false;
  String? _error;
  // Senior
  List<Json> _zones = [];
  String _zone = '';
  LatLng? _point;

  SellerController get c => widget.controller;
  bool get _editing => widget.edit != null;

  @override
  void initState() {
    super.initState();
    if (!_editing && c.isSenior) _loadZones();
    if (_register.text.isNotEmpty) _onRegister(_register.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final t in [_name, _register, _contact, _phone, _address, _note]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _loadZones() async {
    try {
      final z = jsonList(await c.api.get('/zones'));
      if (mounted) setState(() => _zones = z);
    } catch (_) {}
  }

  void _onRegister(String value) {
    final clean = sanitizeRegister(value);
    if (clean != value) {
      _register.value = TextEditingValue(
        text: clean,
        selection: TextSelection.collapsed(offset: clean.length),
      );
    }
    _debounce?.cancel();
    if (registerKind(clean) == null) {
      setState(() {
        _hint = registerProgress(clean);
        _hintColor = AppColors.muted;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _lookup(clean));
  }

  Future<void> _lookup(String register) async {
    var data = _registerCache[register];
    if (data == null) {
      setState(() {
        _hint = registerKind(register) == 'person' ? 'Хувь хүн хайж байна…' : 'Байгууллага хайж байна…';
        _hintColor = AppColors.muted;
      });
      try {
        final res = await c.api.get('/ebarimt/register-lookup', query: {'register': register});
        data = res is Json ? res : <String, dynamic>{};
        _registerCache[register] = data;
      } catch (e) {
        // ⚠ Хайлт бүтэлгүйтвэл бүртгэл ЗОГСОХГҮЙ — ямар алдаа болохыг л хэлнэ.
        if (!mounted) return;
        final status = e is ApiException ? e.status : null;
        setState(() {
          _hint = switch (status) {
            401 || 403 => 'Энэ эрхээр регистр шалгах боломжгүй — админд хэлнэ үү.',
            404 => 'Сервер дээр энэ үйлчилгээ алга — backend шинэчлэгдээгүй байна.',
            final int s => 'Сервер алдаа ($s) — регистр гараар бичигдэнэ.',
            _ => 'Сервер рүү холбогдож чадсангүй — регистр гараар бичигдэнэ.',
          };
          _hintColor = AppColors.muted;
        });
        return;
      }
    }
    if (!mounted || sanitizeRegister(_register.text) != register) return;
    final kind = registerKind(register);
    setState(() {
      if (data!['unavailable'] == true) {
        _hint = data['reason'] == 'demo'
            ? 'Demo горимд улсын бүртгэл рүү хандахгүй — регистр гараар бичигдэнэ.'
            : 'Улсын бүртгэлийн үйлчилгээ хариу өгсөнгүй${str(data['detail']) != null ? ' (${data['detail']})' : ''} — регистр гараар бичигдэнэ.';
        _hintColor = AppColors.muted;
      } else if (data['found'] == true && str(data['name']) != null) {
        _hint = '${kind == 'person' ? 'Хувь хүн: ' : ''}${data['name']}';
        _hintColor = AppColors.success;
        // ⚠ ЗӨВХӨН БАЙГУУЛЛАГЫН нэрийг бөглөнө (хувь хүний нэр дэлгүүрийн нэр биш),
        //   мөн ГАРААР бичсэн нэрийг хэзээ ч дарж бичихгүй.
        final current = _name.text.trim();
        if (kind == 'org' && (current.isEmpty || current == _autoFilledName)) {
          _name.text = '${data['name']}';
          _autoFilledName = _name.text;
        }
      } else {
        _hint = 'Улсын бүртгэлээс олдсонгүй — регистрээ шалгана уу.';
        _hintColor = AppColors.danger;
      }
    });
  }

  Future<void> _takePhoto() async {
    try {
      final img = await captureCameraImage();
      if (img != null && mounted) setState(() => _image = img);
    } catch (e) {
      if (mounted) setState(() => _error = 'Зураг уншихад алдаа гарлаа.');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim();
    final register = _register.text.trim();
    final contact = _contact.text.trim();
    final phone = _phone.text.trim();
    final address = _address.text.trim();
    final note = _note.text.trim();
    final invalid = validateStoreForm(
      name: name,
      register: register,
      contactName: contact,
      phone: phone,
      address: address,
      storeType: _type,
    );
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        // ⚠ Байршил, бүс, төлөв, зээлийн эрх ОГТ илгээгдэхгүй (серверийн цагаан жагсаалт).
        final id = '${widget.edit!['id']}';
        final updated = await c.api.patch('/stores/$id', {
          'name': name,
          'register': register,
          'registerName': ?registerNameFor(register),
          'contactName': contact,
          'phone': phone,
          'address': address,
          'storeType': _type,
          'note': note,
        });
        await c.loadStores();
        c.setMessage(
          AppMessage.success('«${updated is Json ? updated['name'] ?? name : name}» дэлгүүрийн мэдээлэл шинэчлэгдлээ.'),
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final body = <String, dynamic>{
        'name': name,
        'register': register,
        'registerName': ?registerNameFor(register),
        'contactName': contact,
        'phone': phone,
        'address': address,
        'storeType': _type,
        if (note.isNotEmpty) 'note': note,
        if (_image != null) 'images': [_image],
      };
      if (c.isSenior) {
        // Ахлах борлуулагч: GPS шаардахгүй — бүсээ сонгож, байршлыг зургаас заана.
        if (_zone.isEmpty) throw const _FormError('Бүсээ сонгоно уу.');
        final p = _point;
        if (p == null) throw const _FormError('Дэлгүүрийн байршлыг зураг дээр товшиж тэмдэглэнэ үү.');
        body['zone'] = _zone;
        body['location'] = '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';
      } else {
        // Байршил = одоогийн GPS цэг (сервер бүсийн полигон + геофенсээр шалгана).
        final coords = await GeoService.instance.getCoords();
        if (coords == null) {
          throw const _FormError(
            'Байршил тодорхойлж чадсангүй. GPS-ээ асааж, дэлгүүрийн дэргэд зогсоод дахин оролдоно уу.',
          );
        }
        body['location'] = '${coords.lat.toStringAsFixed(6)},${coords.lng.toStringAsFixed(6)}';
        body['lat'] = coords.lat;
        body['lng'] = coords.lng;
      }
      final created = await c.api.post('/stores', body);
      await c.loadStores();
      final createdName = created is Json ? created['name'] ?? name : name;
      if (created is Json && created['id'] != null) c.selectStore('${created['id']}');
      c.setMessage(
        AppMessage.success(
          c.isSenior
              ? '«$createdName» дэлгүүр бүртгэгдлээ — одоо захиалга авах боломжтой.'
              : '«$createdName» дэлгүүр бүртгэгдлээ — одоо захиалга авах боломжтой. Админ шалгаж баталгаажуулна.',
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on _FormError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      final text = SellerController.errorText(
        e,
        _editing ? 'Хадгалахад алдаа гарлаа.' : 'Дэлгүүр бүртгэхэд алдаа гарлаа.',
      );
      setState(() => _error = text);
      if (mounted) alertError(context, text, title: 'Дэлгүүр бүртгэх боломжгүй');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration dec(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Дэлгүүрийн мэдээлэл засах' : 'Шинэ дэлгүүр бүртгэх')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(
              _busy
                  ? (_editing ? 'Хадгалж байна…' : 'Бүртгэж байна…')
                  : (_editing ? 'Хадгалах' : 'Бүртгээд захиалга авах'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _editing
                ? 'Нэр, регистр, хариуцагч, утас, хаяг, төрлийг засна. Бүс, байршил, зээлийн эрхийг зөвхөн админ өөрчилнө.'
                : 'Байршил нь таны одоо зогсож буй GPS цэгээр бүртгэгдэнэ. Бүртгэсний дараа шууд захиалга авах боломжтой; админ шалгаж баталгаажуулна.',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (_error != null) MessageBanner(AppMessage.error(_error!)),
          TextField(controller: _name, maxLength: 160, decoration: dec('Дэлгүүрийн нэр')),
          TextField(
            controller: _register,
            maxLength: 10,
            decoration: dec('Регистр (байгууллага / хувь хүн)', hint: '5327466 эсвэл МА71110326'),
            onChanged: _onRegister,
          ),
          if (_hint != null && _hint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_hint!, style: TextStyle(color: _hintColor, fontSize: 12.5)),
            ),
          TextField(controller: _contact, maxLength: 120, decoration: dec('Хариуцагч')),
          TextField(controller: _phone, maxLength: 30, keyboardType: TextInputType.phone, decoration: dec('Утас')),
          // Төрөл = үнийн шатлал. ⚠ Анхдагч утга ТАВИХГҮЙ — ухамсартай сонголт.
          DropdownButtonFormField<String>(
            initialValue: _type.isEmpty ? null : _type,
            decoration: dec('Дэлгүүрийн төрөл'),
            hint: const Text('Сонгох'),
            items: const [
              DropdownMenuItem(value: 'market', child: Text('Маркет (жижиглэн)')),
              DropdownMenuItem(value: 'wholesale', child: Text('Бөөний төв / зах')),
            ],
            onChanged: (v) => setState(() => _type = v ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLength: 500,
            decoration: dec('Хаяг', hint: 'Дүүрэг, хороо, байр гэх мэт'),
          ),
          TextField(controller: _note, maxLength: 500, decoration: dec('Тайлбар (заавал биш)')),
          if (!_editing) ...[
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Дэлгүүрийн зураг (заавал биш)'),
                ),
                const SizedBox(width: 10),
                if (_image != null)
                  Stack(
                    children: [
                      dataUrlImage('${_image!['imageData']}', size: 64),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkResponse(
                          onTap: () => setState(() => _image = null),
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!c.isSenior)
              const Text(
                'Байршил: одоогийн GPS цэгээр автоматаар тэмдэглэгдэнэ — дэлгүүрийн дэргэд зогсож бүртгэнэ үү.',
                style: TextStyle(color: AppColors.muted),
              ),
            if (c.isSenior) ..._seniorBlock(),
          ],
        ],
      ),
    );
  }

  List<Widget> _seniorBlock() => [
    DropdownButtonFormField<String>(
      initialValue: _zone.isEmpty ? null : _zone,
      decoration: const InputDecoration(labelText: 'Бүс'),
      hint: const Text('Бүс сонгох'),
      items: [for (final z in _zones) DropdownMenuItem(value: '${z['name']}', child: Text('${z['name']}'))],
      onChanged: (v) => setState(() => _zone = v ?? ''),
    ),
    const SizedBox(height: 8),
    const Text('Дэлгүүрийн байршлыг зураг дээр товшиж тэмдэглэнэ.', style: TextStyle(color: AppColors.muted)),
    const SizedBox(height: 8),
    SizedBox(
      height: 280,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(initialCenter: _ubCenter, initialZoom: 12, onTap: (_, ll) => setState(() => _point = ll)),
          children: [
            _tiles(),
            // Бүсийн хил — зөв цэг тавихад хялбар.
            PolygonLayer(
              polygons: [
                for (final z in _zones)
                  if (_polygonOf(z).length >= 3)
                    Polygon(
                      points: [for (final p in _polygonOf(z)) LatLng(p[0], p[1])],
                      color: Color(zoneTone('${z['name']}', str(z['color']))).withValues(alpha: 0.06),
                      borderColor: Color(zoneTone('${z['name']}', str(z['color']))),
                      borderStrokeWidth: 1.5,
                    ),
              ],
            ),
            if (_point != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _point!,
                    width: 34,
                    height: 34,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: AppColors.brand, size: 34),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  ];
}

class _FormError implements Exception {
  final String message;
  const _FormError(this.message);
}

// ── Харилцагчийн дэлгэрэнгүй ─────────────────────────────────────────────────
Future<void> openCustomerDetail(BuildContext context, SellerController c, String storeId) {
  // ⚠ `stores` нь ЗӨВХӨН өөрийн бүсийн идэвхтэй дэлгүүр — зээлтэй дэлгүүр өөр бүс
  //   рүү шилжсэн бол зээлийн мөрөөр нөхнө.
  final store = c.storeById(storeId) ?? c.creditStoreFallback(storeId);
  if (store == null) return Future.value();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _CustomerDetailScreen(controller: c, store: store),
    ),
  );
}

class _CustomerDetailScreen extends StatefulWidget {
  final SellerController controller;
  final Json store;
  const _CustomerDetailScreen({required this.controller, required this.store});

  @override
  State<_CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<_CustomerDetailScreen> {
  Json? _balance;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.controller.api.get('/stores/${widget.store['id']}/balance');
      if (mounted) setState(() => _balance = b is Json ? b : {});
    } catch (_) {
      if (mounted) setState(() => _error = 'Тооцоо ачаалахад алдаа гарлаа.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = widget.store;
    // ⚠ Зээлийн мөрөөс сэргээсэн ХЭСЭГЧИЛСЭН бичлэг дээр засах товч гаргахгүй —
    //   регистр, хаяг, төрөл байхгүй тул хадгалбал тэд хоосорно.
    final editable = c.storeById('${s['id']}') != null;
    final location = str(s['location']) ?? str(s['address']);
    return Scaffold(
      appBar: AppBar(title: const Text('Харилцагч')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              StoreImage(url: str(s['coverImageUrl']), size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s['name'] ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        Text('#${str(s['storeCode']) ?? '-'}', style: const TextStyle(color: AppColors.muted)),
                        if (str(s['zone']) != null) Tag('Бүс: ${s['zone']}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow('Байгууллагын регистр', str(s['register']) ?? '—'),
          InfoRow('Хариуцагч', str(s['contactName']) ?? '—'),
          InfoRow('Утас', str(s['phone']) ?? '—'),
          InfoRow('Бүс', str(s['zone']) ?? '—'),
          InfoRow('Хаяг', str(s['address']) ?? '—'),
          InfoRow('Дундаж борлуулалт', formatMoney(c.storeAverageOrder('${s['id']}'))),
          InfoRow('Борлуулагч', c.user.displayName),
          InfoRow('Бүртгэсэн', formatDateTime(s['createdAt'])),
          InfoRow('Шинэчилсэн', formatDateTime(s['updatedAt'])),
          const SizedBox(height: 12),
          Text('Зээлийн тооцоо', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.muted))
          else if (_balance == null)
            const LoadingState('Ачааллаж байна…')
          else
            CreditCard(balance: _balance!),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (str(s['phone']) != null)
                OutlinedButton.icon(
                  onPressed: () => callPhone(str(s['phone'])),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Залгах'),
                ),
              if (location != null)
                OutlinedButton.icon(
                  onPressed: () => openDirections(str(s['location']), str(s['address'])),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Газрын зураг'),
                ),
              if (editable)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    openStoreForm(context, c, edit: s);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Мэдээлэл засах'),
                ),
              if (editable)
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    c.selectStore('${s['id']}');
                  },
                  child: const Text('Захиалга авах'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Зээлийн тооцооны карт — «боломжит зээл» + ашигласан хувийн мөр + жижиг stat-ууд.
class CreditCard extends StatelessWidget {
  final Json balance;
  const CreditCard({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    final noCredit = balance['available'] == null;
    final limit = toNum(balance['effectiveLimit']);
    final outstanding = toNum(balance['outstanding']);
    final usedPct = limit > 0 ? (outstanding / limit).clamp(0, 1).toDouble() : 0.0;
    final over = balance['overLimit'] == true;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: over ? AppColors.dangerSoft : const Color(0xFFF3FAF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: over ? const Color(0xFFF2C4C4) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Авах боломжтой зээл', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    Text(
                      noCredit ? 'Зээлгүй' : formatMoney(toNum(balance['available'])),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (over) const Tag('Эрх хэтэрсэн', color: AppColors.danger, background: AppColors.dangerSoft),
            ],
          ),
          if (limit > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: usedPct,
              minHeight: 6,
              backgroundColor: AppColors.border,
              color: over ? AppColors.danger : AppColors.brand,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Text('Ашигласан: ${formatMoney(outstanding)}', style: const TextStyle(fontSize: 12))),
                Text('Эрх: ${formatMoney(limit)}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              stat(
                'Зээлийн эрх',
                balance['creditLimit'] != null && toNum(balance['creditLimit']) > 0 ? formatMoney(limit) : 'Хязгааргүй',
              ),
              stat('Нийт авсан', formatMoney(toNum(balance['charges']))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              stat('Нийт төлсөн', formatMoney(toNum(balance['paid']))),
              stat('Үлдэгдэл зээл', formatMoney(outstanding)),
            ],
          ),
        ],
      ),
    );
  }
}
