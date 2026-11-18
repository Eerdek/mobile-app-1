import 'package:flutter/material.dart';

import '../../core/date_range.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/links.dart';
import '../../core/ui.dart';
import 'seller_controller.dart';
import 'seller_logic.dart';
import 'seller_widgets.dart';
import 'store_sheets.dart';

/// Барааны өрөлт — дэлгүүр сонгож, өрөлтийг КАМЕРААР дарсан зургаар
/// баталгаажуулна. Дармагц «Илгээх үү?» баталгаажуулалт гарч шууд илгээнэ.
class PlacementPage extends StatefulWidget {
  final SellerController controller;
  const PlacementPage({super.key, required this.controller});

  @override
  State<PlacementPage> createState() => _PlacementPageState();
}

class _PlacementPageState extends State<PlacementPage> {
  String? _storeId;
  final _note = TextEditingController();
  List<Json>? _rows;
  String? _rowsError;
  DateRange _range = DateRange.preset(RangePreset.all);
  AppMessage? _message;
  // GPS + base64 upload удаан — давхар илгээхээс сэргийлнэ.
  bool _sending = false;

  SellerController get c => widget.controller;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _storeId;
    if (id == null) return;
    setState(() {
      _rows = null;
      _rowsError = null;
    });
    try {
      final rows = jsonList(await c.api.get('/product-placements', query: {'storeId': id}));
      if (mounted && _storeId == id) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _rowsError = SellerController.errorText(e, 'Татахад алдаа гарлаа.'));
    }
  }

  Future<void> _pickStore() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StorePickSheet(stores: c.stores),
    );
    if (id == null) return;
    setState(() {
      _storeId = id;
      _message = null;
    });
    _load();
  }

  Future<void> _capture() async {
    final storeId = _storeId;
    if (storeId == null) {
      setState(() => _message = const AppMessage.error('Эхлээд дэлгүүр сонгоно уу.'));
      return;
    }
    Json? image;
    try {
      image = await captureCameraImage();
    } catch (_) {
      setState(() => _message = const AppMessage.error('Зураг уншихад алдаа гарлаа.'));
      return;
    }
    if (image == null || !mounted) return;
    final store = c.storeById(storeId);
    final send = await showModalBottomSheet<bool>(
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
                'Өрөлтийн зураг илгээх үү?',
                style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text('${store?['name'] ?? '—'}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              Center(child: dataUrlImage('${image!['imageData']}', size: 200)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.of(sheet).pop(false), child: const Text('Болих')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(onPressed: () => Navigator.of(sheet).pop(true), child: const Text('Илгээх')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (send != true || !mounted) return;
    await _send(storeId, image);
  }

  Future<void> _send(String storeId, Json image) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final note = _note.text.trim();
      final coords = c.isSenior ? null : await GeoService.instance.getCoords();
      if (coords == null && c.geofenceCheckOn) {
        throw const _Msg('Байршил тодорхойлж чадсангүй. GPS-ээ асааж, дэлгүүр дээрээ ирээд дахин оролдоно уу.');
      }
      // Дэлгүүрээс хол бол upload-аас ӨМНӨ ойлгомжтой алдаа. Босго нь СЕРВЕРИЙН
      // геофенс радиустай ижил — зөрвөл клиент «OK» гээд сервер няцаана.
      final store = c.storeById(storeId);
      final target = coords != null && c.geofenceCheckOn ? parseLatLng(str(store?['location'])) : null;
      if (coords != null && target != null) {
        final radius = GeoService.instance.geofenceRadius;
        final distance = distanceMeters(coords.lat, coords.lng, target.$1, target.$2);
        if (distance > radius) {
          throw _Msg(
            'Та «${store?['name']}» дэлгүүрээс ≈${distance.round()}м зайд байна — '
            'өрөлтийг дэлгүүрийн ${radius.round()}м-ийн дотор очиж баталгаажуулна.',
          );
        }
      }
      await c.api.post('/product-placements', {
        'storeId': storeId,
        if (note.isNotEmpty) 'note': note,
        'images': [image],
        'lat': ?coords?.lat,
        'lng': ?coords?.lng,
      });
      _note.clear();
      if (!mounted) return;
      setState(() => _message = const AppMessage.success('Барааны өрөлт илгээгдлээ.'));
      await _load();
    } on _Msg catch (e) {
      if (!mounted) return;
      setState(() => _message = AppMessage.error(e.text));
      alertError(context, e.text, title: 'Өрөлт');
    } catch (e) {
      if (!mounted) return;
      final text = SellerController.errorText(e, 'Илгээхэд алдаа гарлаа.');
      setState(() => _message = AppMessage.error(text));
      alertError(context, text, title: 'Өрөлт');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = c.storeById(_storeId);
    // Дэлгүүр жагсаалтаас алга болсон бол сонголтыг цэвэрлэнэ.
    if (_storeId != null && store == null && c.stores.isNotEmpty) _storeId = null;
    final list = (_rows ?? const <Json>[]).where((r) => _range.contains(r['createdAt'])).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        MessageBanner(_message, onClose: () => setState(() => _message = null)),
        SectionCard(
          title: 'Барааны өрөлт',
          subtitle: 'Дэлгүүр сонгож, барааны өрөлт зөв эсэхийг зургаар баталгаажуулна',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickStore,
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(
                  store == null ? 'Дэлгүүр сонгох' : '${store['name']} (#${str(store['storeCode']) ?? '-'})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Тэмдэглэл', hintText: 'Өрөлтийн тайлбар (заавал биш)'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _capture,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_camera_outlined),
                label: Text(_sending ? 'Илгээж байна…' : 'Камераар зураг дарах'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Өмнөх өрөлтүүд',
          subtitle: 'Сонгосон дэлгүүрийн өрөлтийн тэмдэглэл, зургийн түүх',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
              const SizedBox(height: 10),
              if (_storeId == null)
                const EmptyState('Дэлгүүр сонгоно уу.')
              else if (_rowsError != null)
                EmptyState(_rowsError!)
              else if (_rows == null)
                const LoadingState('Ачаалж байна...')
              else if (list.isEmpty)
                EmptyState(
                  _rows!.isEmpty ? 'Энэ дэлгүүрийн өрөлтийн зураг алга.' : 'Энэ хугацаанд өрөлтийн зураг алга.',
                )
              else
                for (final r in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatDateTime(r['createdAt']),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${jsonList(r['images']).length} зураг',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                        if (str(r['note']) != null) Text('${r['note']}'),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final img in jsonList(r['images']))
                              if (str(img['url']) != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    '${img['url']}',
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const SizedBox(width: 96, height: 96),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Msg implements Exception {
  final String text;
  const _Msg(this.text);
}

/// Хайлттай дэлгүүрийн сонголт (web-ийн combobox).
class _StorePickSheet extends StatefulWidget {
  final List<Json> stores;
  const _StorePickSheet({required this.stores});

  @override
  State<_StorePickSheet> createState() => _StorePickSheetState();
}

class _StorePickSheetState extends State<_StorePickSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = widget.stores
        .where(
          (s) =>
              q.isEmpty ||
              [s['name'], s['storeCode'], s['phone'], s['address']].any((f) => '${f ?? ''}'.toLowerCase().contains(q)),
        )
        .take(40)
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              SearchField(hint: 'Нэр, код, утсаар хайх…', onChanged: (v) => setState(() => _q = v)),
              const SizedBox(height: 8),
              Expanded(
                child: rows.isEmpty
                    ? const EmptyState('Тохирох дэлгүүр олдсонгүй.')
                    : ListView(
                        children: [
                          for (final s in rows)
                            ListTile(
                              title: Text('${s['name'] ?? ''}'),
                              subtitle: Text(
                                '#${str(s['storeCode']) ?? '-'}${str(s['address']) != null ? ' · ${s['address']}' : ''}',
                              ),
                              onTap: () => Navigator.of(context).pop('${s['id']}'),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
