import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/excel_export.dart';
import '../../core/format.dart';
import '../../core/ui.dart';
import 'factory_logic.dart';
import 'factory_models.dart';
import 'factory_widgets.dart';

// Гарсан барааны түүх — хүргэгдсэн захиалгын нэгтгэл (хүргэсэн огноогоор).
// Хугацааны хүрээ нь бүх аппад ижил: Бүгд / Өнөөдөр / 7 хоног / Энэ сар.
enum _Preset { all, today, week, month }

class HistoryTab extends StatefulWidget {
  final ApiClient api;
  /// Tab руу дахин ороход shell дохио өгнө — web шиг шинэчилнэ.
  final Listenable? revisit;
  const HistoryTab({super.key, required this.api, this.revisit});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  DateTime? _from;
  DateTime? _to;
  bool _byStore = false;
  bool _loading = false;
  AppMessage? _message;
  ProductionSummary _data = ProductionSummary.empty;
  final Set<String> _open = {};

  // Хамгийн сүүлд илгээсэн хүсэлт л үр дүнгээ бичнэ (хуучин муж дарж бичихгүй).
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    widget.revisit?.addListener(_load);
    _applyPreset(_Preset.today);
  }

  @override
  void dispose() {
    widget.revisit?.removeListener(_load);
    super.dispose();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  (DateTime?, DateTime?) _rangeOf(_Preset p) => switch (p) {
    _Preset.all => (null, null),
    _Preset.today => (_today, _today),
    _Preset.week => (_today.subtract(const Duration(days: 6)), _today),
    _Preset.month => (DateTime(_today.year, _today.month, 1), _today),
  };

  _Preset? get _activePreset {
    for (final p in _Preset.values) {
      final r = _rangeOf(p);
      if (r.$1 == _from && r.$2 == _to) return p;
    }
    return null;
  }

  void _applyPreset(_Preset p) {
    final r = _rangeOf(p);
    _from = r.$1;
    _to = r.$2;
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      // Шинэ мужийн өгөгдөл ирэх хүртэл өмнөх мужийнхыг харуулахгүй.
      _data = ProductionSummary.empty;
    });
    try {
      // [from, to) ISO хязгаар — локал өдрийн хилээр.
      final res = await widget.api.get(
        '/orders/production-summary',
        query: {
          'view': 'delivered',
          'from': _from?.toUtc().toIso8601String(),
          'to': _to?.add(const Duration(days: 1)).toUtc().toIso8601String(),
        },
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = ProductionSummary.fromJson(res);
        _message = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = ProductionSummary.empty;
        _message = AppMessage.error(e is ApiException ? e.message : 'Түүх ачаалахад алдаа гарлаа.');
      });
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? _today,
      firstDate: DateTime(2024),
      lastDate: _today.add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      from ? _from = picked : _to = picked;
      // Web-тэй адил эхлэл > төгсгөл бол сольж тавина.
      final f = _from, t = _to;
      if (f != null && t != null && f.isAfter(t)) {
        _from = t;
        _to = f;
      }
    });
    _load();
  }

  Future<void> _export() async {
    if (_data.products.isEmpty) {
      setState(() => _message = const AppMessage.error('Татах бараа алга байна.'));
      return;
    }
    try {
      await shareExcel(
        fileBaseName: 'Гарсан бараа ${ymd(DateTime.now())}',
        sheetName: 'Гарсан бараа',
        rows: buildProductExcelRows(_data.products),
      );
    } catch (e) {
      setState(() => _message = AppMessage.error('Excel үүсгэхэд алдаа гарлаа: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _data.totals;
    final active = _activePreset;
    const labels = {_Preset.all: 'Бүгд', _Preset.today: 'Өнөөдөр', _Preset.week: '7 хоног', _Preset.month: 'Энэ сар'};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _Preset.values)
                ChoiceChip(label: Text(labels[p]!), selected: active == p, onSelected: (_) => _applyPreset(p)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(_from == null ? 'Эхлэх' : ymd(_from!)),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(_to == null ? 'Дуусах' : ymd(_to!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MessageBanner(_message, onClose: () => setState(() => _message = null)),
          SectionCard(
            title: 'Гарсан барааны нэгтгэл',
            subtitle:
                '${t.productKinds} төрлийн ${formatQty(t.totalQty)} ширхэг бараа · '
                '${t.orderCount} захиалга · ${t.storeCount} дэлгүүр',
            actions: [IconButton(tooltip: 'Excel', icon: const Icon(Icons.download_outlined), onPressed: _export)],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Хоёулаа ЯГ НЭГ хариунаас — нийлбэр хэзээ ч зөрөхгүй.
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Бараагаар')),
                    ButtonSegment(value: true, label: Text('Дэлгүүрээр')),
                  ],
                  selected: {_byStore},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _byStore = v.first),
                ),
                const SizedBox(height: 10),
                if (_loading && _data.products.isEmpty)
                  const LoadingState('Түүхийг ачаалж байна…')
                else if (_message?.kind == MessageKind.error && _data.products.isEmpty)
                  const EmptyState('Түүх ачаалж чадсангүй — доош татаж дахин оролдоно уу.')
                else if (_byStore ? _data.stores.isEmpty : _data.products.isEmpty)
                  const EmptyState('Сонгосон хугацаанд хүргэгдсэн захиалга алга.')
                else if (_byStore)
                  for (final s in _data.stores) _storeTile(s)
                else
                  for (final g in groupByCategory(_data.products)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                      child: Text(
                        '${g.name.toUpperCase()} · ${g.items.length} төрөл · ${formatQty(g.totalQty)} ш',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.muted),
                      ),
                    ),
                    for (final p in g.items) _productTile(p),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productTile(SummaryProduct p) {
    final key = 'p:${p.productId ?? p.name}';
    // ⚠ Түүх дээр бэлтгэлийн явц ХАРУУЛАХГҮЙ — хүргэгдсэн ачаа бэлдээгүй мэт уншигдана.
    final split = splitProduct(p);
    return ExpandTile(
      key: ValueKey(key),
      open: _open.contains(key),
      onToggle: (o) => setState(() => o ? _open.add(key) : _open.remove(key)),
      title: Text(p.name),
      subtitle: Text(
        '${p.productCode != null ? 'Код ${p.productCode} · ' : ''}${p.orderCount} захиалга',
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
      trailing: QtyLabel(split.locked, split.unlocked, p.unitLabel),
      children: [
        for (final d in p.byDelivery)
          AccRow(d.label, QtyLabel(splitPart(d).locked, splitPart(d).unlocked, p.unitLabel)),
      ],
    );
  }

  Widget _storeTile(SummaryStore s) {
    final key = 's:${s.storeCode ?? s.storeName}';
    return ExpandTile(
      key: ValueKey(key),
      open: _open.contains(key),
      onToggle: (o) => setState(() => o ? _open.add(key) : _open.remove(key)),
      title: Text(s.storeName),
      subtitle: Text(
        '${s.storeCode != null ? '№${s.storeCode} · ' : ''}${s.orderCount} захиалга · ${s.items.length} төрөл',
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
      trailing: Text('${formatQty(s.totalQty)} ш', style: const TextStyle(fontWeight: FontWeight.w700)),
      children: s.items.isEmpty
          ? const [EmptyState('Барааны мэдээлэл алга.')]
          : [
              for (final i in s.items)
                AccRow(
                  i.name,
                  Text('${formatQty(i.qty)} ${i.unit ?? 'ш'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
    );
  }
}
