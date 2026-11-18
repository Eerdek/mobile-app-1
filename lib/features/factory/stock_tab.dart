import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/ui.dart';
import 'factory_models.dart';

// ⚠ ХОЁР ТӨРЛИЙН ХАСАЛТ ХОЁР ӨӨР МӨЧИД болдгийг ойлгуулах нь энэ хуудасны
//   гол ажил: түүхий эд + шошго → ҮЙЛДВЭРЛЭХ үед (технологийн картаар),
//   бэлэн бараа → ГАРАХ үед (түгээгчид өгөхөд).
enum StockKind { product, raw, label }

const Map<StockKind, (String, String, String)> _stockMeta = {
  StockKind.product: ('Бэлэн бараа', 'Үйлдвэрлэхэд нэмэгдэж, түгээгчид өгөхөд хасагдана', 'Идэвхтэй бараа алга.'),
  StockKind.raw: (
    'Түүхий эд',
    'Худалдан авалтаар нэмэгдэж, үйлдвэрлэх үед технологийн картаар хасагдана',
    'Түүхий эд бүртгэгдээгүй байна.',
  ),
  StockKind.label: (
    'Шошго',
    'Нэг бүтээгдэхүүнд хэдэн ширхэг зарцуулагдахыг технологийн картад бичнэ',
    'Шошго бүртгэгдээгүй байна.',
  ),
};

const Map<String, String> _moveLabel = {
  'produce': 'Үйлдвэрлэв',
  'consume': 'Үйлдвэрлэлд зарцуулав',
  'purchase': 'Нэмэв',
  'issue': 'Түгээгчид гарав',
  'adjust': 'Тооллого / засвар',
};

/// Үлдэгдлийн өгөгдөл — технологийн картын материал сонгогч ч үүнийг хэрэглэнэ.
class StockStore extends ChangeNotifier {
  final ApiClient api;
  StockStore(this.api);

  StockData? data;
  bool loading = false;
  AppMessage? message;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      data = StockData.fromJson(await api.get('/factory/stock'));
      message = null;
    } catch (e) {
      data = null;
      message = AppMessage.error(e is ApiException ? e.message : 'Үлдэгдэл ачаалахад алдаа гарлаа.');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setMessage(AppMessage? m) {
    message = m;
    notifyListeners();
  }
}

class StockTab extends StatefulWidget {
  final StockStore store;

  /// Tab руу дахин ороход shell дохио өгнө — web шиг шинэчилнэ.
  final Listenable? revisit;
  const StockTab({super.key, required this.store, this.revisit});

  @override
  State<StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> {
  StockKind _tab = StockKind.product;
  String _search = '';

  StockStore get s => widget.store;
  ApiClient get api => s.api;

  @override
  void initState() {
    super.initState();
    widget.revisit?.addListener(_onRevisit);
    s.load();
  }

  @override
  void dispose() {
    widget.revisit?.removeListener(_onRevisit);
    super.dispose();
  }

  void _onRevisit() {
    if (!s.loading) s.load();
  }

  List<StockRow> _rows() {
    final data = s.data;
    if (data == null) return const [];
    final rows = _tab == StockKind.product
        ? data.products
        : data.materials.where((m) => m.kind == (_tab == StockKind.raw ? 'raw' : 'label')).toList();
    final term = _search.trim().toLowerCase();
    if (term.isEmpty) return rows;
    return rows.where((r) => r.name.toLowerCase().contains(term)).toList();
  }

  String _err(Object e) => e is ApiException ? e.message : 'Хадгалахад алдаа гарлаа.';

  // ⚠ Удаан сүлжээнд «Үйлдвэрлэв»-ийг дахин дарвал үйлдвэрлэл 2 бүртгэгдэж,
  //   түүхий эд 2 дахин хасагдана — нэг үйлдэл дуустал шинийг нээхгүй.
  bool _busy = false;

  bool _blockedByBusy() {
    if (_busy) s.setMessage(const AppMessage.warning('Өмнөх бүртгэл хадгалагдаж байна — түр хүлээнэ үү.'));
    return _busy;
  }

  Future<void> _saving(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Үйлдвэрлэл бүртгэх / түүхий эд нэмэх ────────────────────────────────
  Future<void> _add(StockRow row) async {
    if (_blockedByBusy()) return;
    final values = await showPromptDialog(
      context,
      title: row.isProduct ? 'Үйлдвэрлэл бүртгэх' : 'Түүхий эд нэмэх',
      message: row.isProduct
          ? row.hasTechCard
                ? 'Технологийн картаар түүхий эд ба шошго автоматаар хасагдана.'
                : 'Анхаар: технологийн карт үүсээгүй тул түүхий эд хасагдахгүй.'
          : 'Худалдан авсан хэмжээгээ бичнэ үү.',
      fields: [
        PromptField('qty', '${row.name} — тоо (${row.unit ?? ''})', number: true, required: true),
        const PromptField('note', 'Тайлбар', hint: 'Заавал биш'),
      ],
      confirmLabel: row.isProduct ? 'Бүртгэх' : 'Нэмэх',
    );
    if (values == null) return;
    final qty = num.tryParse(values['qty'] ?? '');
    if (qty == null || qty <= 0) {
      s.setMessage(const AppMessage.error('Тоо эерэг байх ёстой.'));
      return;
    }
    final note = (values['note'] ?? '').isEmpty ? null : values['note'];
    if (_blockedByBusy()) return;
    await _saving(() async {
      try {
        if (row.isProduct) {
          final res = await api.post('/factory/produce', {'productId': row.id, 'qty': qty, 'note': note});
          final warnings = res is Map && res['warnings'] is List
              ? (res['warnings'] as List).whereType<Map>().toList()
              : const [];
          // ⚠ Дутсан түүхий эд нь АЛДАА БИШ — бүртгэл орсон. Гэхдээ юу дутсаныг нэрлэнэ.
          s.setMessage(
            warnings.isEmpty
                ? const AppMessage.success('Үйлдвэрлэл бүртгэгдлээ.')
                : AppMessage.warning(
                    'Бүртгэгдлээ. Дутуу: ${warnings.map((w) {
                      final unit = w['unit'] != null ? ' ${w['unit']}' : '';
                      return '${w['materialName']} ${formatAmount(toNum(w['short']))}$unit';
                    }).join(', ')}',
                  ),
          );
        } else {
          await api.post('/factory/stock/adjust', {'materialId': row.id, 'mode': 'add', 'qty': qty, 'note': note});
          s.setMessage(const AppMessage.success('Үлдэгдэл нэмэгдлээ.'));
        }
        final keep = s.message;
        await s.load();
        s.setMessage(keep);
      } catch (e) {
        s.setMessage(AppMessage.error(_err(e)));
      }
    });
  }

  // ── Тооллого — үлдэгдлийг ЯГ тогтооно ───────────────────────────────────
  Future<void> _count(StockRow row) async {
    if (_blockedByBusy()) return;
    final values = await showPromptDialog(
      context,
      title: 'Тооллого',
      message: '${row.name} — бодит үлдэгдлийг бичнэ үү. Одоогийн бүртгэл: ${formatAmount(row.balance)}',
      fields: [
        PromptField(
          'qty',
          'Бодит үлдэгдэл (${row.unit ?? ''})',
          number: true,
          required: true,
          initial: row.balance == row.balance.roundToDouble() ? '${row.balance.round()}' : '${row.balance}',
        ),
        const PromptField('note', 'Шалтгаан', hint: 'Заавал биш'),
      ],
      confirmLabel: 'Тогтоох',
    );
    if (values == null) return;
    final qty = num.tryParse(values['qty'] ?? '');
    if (qty == null || qty < 0) {
      s.setMessage(const AppMessage.error('Тоо сөрөг байж болохгүй.'));
      return;
    }
    if (_blockedByBusy()) return;
    await _saving(() async {
      try {
        await api.post('/factory/stock/adjust', {
          row.isProduct ? 'productId' : 'materialId': row.id,
          'mode': 'set',
          'qty': qty,
          'note': (values['note'] ?? '').isEmpty ? null : values['note'],
        });
        await s.load();
        s.setMessage(const AppMessage.success('Тооллого бүртгэгдлээ.'));
      } catch (e) {
        s.setMessage(AppMessage.error(_err(e)));
      }
    });
  }

  // «Яагаад ийм тоо болов» — үлдэгдэл нь мөрүүдийн нийлбэр.
  Future<void> _moves(StockRow row) async {
    try {
      final res = await api.get(
        '/factory/stock/moves',
        query: {row.isProduct ? 'productId' : 'materialId': row.id, 'limit': '30'},
      );
      final moves = parseList(res, StockMove.fromJson);
      if (!mounted) return;
      await showInfoDialog(
        context,
        title: '${row.name} — хөдөлгөөн',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Одоогийн үлдэгдэл: ${formatAmount(row.balance)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (moves.isEmpty) const Text('Хөдөлгөөн бүртгэгдээгүй байна.'),
            for (final m in moves)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 82,
                      child: Text(
                        shortDateTime(m.createdAt),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${m.qty > 0 ? '+' : '−'}${formatAmount(m.qty.abs())}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: m.qty > 0 ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                    Expanded(child: Text('${_moveLabel[m.reason] ?? m.reason}${m.note != null ? ' · ${m.note}' : ''}')),
                  ],
                ),
              ),
          ],
        ),
      );
    } catch (e) {
      s.setMessage(AppMessage.error(e is ApiException ? e.message : 'Түүх уншихад алдаа гарлаа.'));
    }
  }

  Future<void> _materialForm(StockRow? existing) async {
    if (_blockedByBusy()) return;
    final values = await showPromptDialog(
      context,
      title: existing != null ? 'Материал засах' : 'Материал нэмэх',
      fields: [
        PromptField('name', 'Нэр', required: true, initial: existing?.name),
        PromptField(
          'unit',
          'Нэгж (ширхэг / кг / гр / л)',
          required: true,
          initial: existing?.unit ?? (_tab == StockKind.label ? 'ширхэг' : 'кг'),
        ),
      ],
    );
    if (values == null || _blockedByBusy()) return;
    await _saving(() async {
      try {
        if (existing != null) {
          await api.patch('/factory/materials/${Uri.encodeComponent(existing.id)}', {
            'name': values['name'],
            'unit': values['unit'],
          });
        } else {
          await api.post('/factory/materials', {
            'name': values['name'],
            'unit': values['unit'],
            'kind': _tab == StockKind.label ? 'label' : 'raw',
          });
        }
        await s.load();
        s.setMessage(const AppMessage.success('Хадгалагдлаа.'));
      } catch (e) {
        s.setMessage(AppMessage.error(_err(e)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = _stockMeta[_tab]!;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final rows = _rows();
        return RefreshIndicator(
          onRefresh: s.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 3),
              SegmentedButton<StockKind>(
                segments: const [
                  ButtonSegment(value: StockKind.product, label: Text('Бэлэн бараа')),
                  ButtonSegment(value: StockKind.raw, label: Text('Түүхий эд')),
                  ButtonSegment(value: StockKind.label, label: Text('Шошго')),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
              const SizedBox(height: 12),
              MessageBanner(s.message, onClose: () => s.setMessage(null)),
              SectionCard(
                title: meta.$1,
                subtitle: meta.$2,
                actions: [
                  // «Материал нэмэх» нь зөвхөн түүхий эд/шошгонд — бэлэн бараа каталогоос ирдэг.
                  if (_tab != StockKind.product)
                    IconButton(
                      tooltip: 'Материал нэмэх',
                      icon: const Icon(Icons.add),
                      onPressed: () => _materialForm(null),
                    ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Хайх…'),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 10),
                    if (s.loading && s.data == null)
                      const LoadingState('Ачаалж байна…')
                    else if (rows.isEmpty)
                      EmptyState(meta.$3)
                    else
                      for (final row in rows)
                        _StockRowTile(row: row, onAdd: _add, onCount: _count, onMoves: _moves, onEdit: _materialForm),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StockRowTile extends StatelessWidget {
  final StockRow row;
  final void Function(StockRow) onAdd;
  final void Function(StockRow) onCount;
  final void Function(StockRow) onMoves;
  final void Function(StockRow) onEdit;

  const _StockRowTile({
    required this.row,
    required this.onAdd,
    required this.onCount,
    required this.onMoves,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final empty = row.balance <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: empty ? AppColors.dangerSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: empty ? const Color(0xFFF2C4C4) : AppColors.border),
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
                    Text(row.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Wrap(
                      spacing: 6,
                      children: [
                        Text(row.unit ?? '', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                        if (row.isProduct && !row.hasTechCard) const Tag.warning('карт алга'),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                formatAmount(row.balance),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: empty ? AppColors.danger : AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton(
                onPressed: () => onAdd(row),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(row.isProduct ? 'Үйлдвэрлэв' : 'Нэмэх'),
              ),
              OutlinedButton(
                onPressed: () => onCount(row),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Тооллого'),
              ),
              OutlinedButton(
                onPressed: () => onMoves(row),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Түүх'),
              ),
              if (!row.isProduct)
                OutlinedButton(
                  onPressed: () => onEdit(row),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Засах'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
