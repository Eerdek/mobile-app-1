import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/ui.dart';
import 'factory_models.dart';
import 'factory_widgets.dart';
import 'stock_tab.dart';

// Бэлтгэх заавар (технологийн карт). ⚠ Орц ба алхмууд НЭГ картад: орц нь
// үйлдвэрлэл бүрд түүхий эд/шошго хасах ҮНДЭС, алхмууд нь хүнд зориулсан.
class TechCardsTab extends StatefulWidget {
  final StockStore stock;
  /// Tab руу дахин ороход shell дохио өгнө — web шиг шинэчилнэ.
  final Listenable? revisit;
  const TechCardsTab({super.key, required this.stock, this.revisit});

  @override
  State<TechCardsTab> createState() => _TechCardsTabState();
}

class _DraftItem {
  String materialId;
  final TextEditingController qty;
  _DraftItem(this.materialId, String qty) : qty = TextEditingController(text: qty);
}

class _Draft {
  final String productId;
  final List<_DraftItem> items;
  final List<TextEditingController> steps;
  _Draft(this.productId, this.items, this.steps);

  void dispose() {
    for (final i in items) {
      i.qty.dispose();
    }
    for (final s in steps) {
      s.dispose();
    }
  }
}

class _TechCardsTabState extends State<TechCardsTab> {
  List<TechCard>? _cards;
  AppMessage? _message;
  String _search = '';
  bool _onlyMissing = false;
  final Set<String> _open = {};
  _Draft? _draft;
  bool _saving = false;

  ApiClient get api => widget.stock.api;

  @override
  void initState() {
    super.initState();
    widget.revisit?.addListener(_onRevisit);
    _load();
  }

  @override
  void dispose() {
    widget.revisit?.removeListener(_onRevisit);
    _draft?.dispose();
    super.dispose();
  }

  // ⚠ Засаж буй ноорог байвал дарж бичихгүй.
  void _onRevisit() {
    if (_draft == null && !_saving) _load();
  }

  Future<void> _load() async {
    // ⚠ Материалын жагсаалт орцны сонгогчид ЗААВАЛ хэрэгтэй.
    if (widget.stock.data == null) await widget.stock.load();
    try {
      final cards = parseList(await api.get('/factory/tech-cards'), TechCard.fromJson);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _message = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cards = const [];
        _message = AppMessage.error(e is ApiException ? e.message : 'Заавар ачаалахад алдаа гарлаа.');
      });
    }
  }

  void _startEdit(TechCard card) {
    _draft?.dispose();
    setState(() {
      _draft = _Draft(
        card.productId,
        // ⚠ formatAmount 3 орон хүртэл тоймлодог — 0.0004 нь «0» болж хадгалахад
        //   орц чимээгүй устана. Засварт ТҮҮХИЙ утгыг өгнө (web-тэй адил).
        [for (final i in card.items) _DraftItem(i.materialId, _rawQty(i.qty))],
        [for (final s in card.steps) TextEditingController(text: s)],
      );
      _open.add(card.productId);
    });
  }

  static String _rawQty(num q) => q == q.roundToDouble() ? '${q.round()}' : '$q';

  Future<void> _cancel() async {
    final ok = await confirmDialog(
      context,
      title: 'Засварыг болих',
      message: 'Хадгалаагүй өөрчлөлт устна. Болих уу?',
      confirmLabel: 'Болих',
      danger: true,
    );
    if (!ok || !mounted) return;
    _draft?.dispose();
    setState(() => _draft = null);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    final items = <Map<String, Object>>[];
    final seen = <String>{};
    for (final i in draft.items) {
      final qty = num.tryParse(i.qty.text.trim().replaceAll(',', '.')) ?? 0;
      if (i.materialId.isEmpty || qty <= 0) continue;
      if (!seen.add(i.materialId)) {
        setState(() => _message = const AppMessage.error('Нэг материал хоёр удаа орсон байна.'));
        return;
      }
      items.add({'materialId': i.materialId, 'qty': qty});
    }
    final steps = draft.steps.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    setState(() => _saving = true);
    try {
      await api.put('/factory/tech-cards/${Uri.encodeComponent(draft.productId)}', {'items': items, 'steps': steps});
      draft.dispose();
      _draft = null;
      await _load();
      if (mounted) setState(() => _message = const AppMessage.success('Технологийн карт хадгалагдлаа.'));
    } catch (e) {
      if (mounted) {
        setState(() => _message = AppMessage.error(e is ApiException ? e.message : 'Хадгалахад алдаа гарлаа.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    final term = _search.trim().toLowerCase();
    final rows = (cards ?? const <TechCard>[]).where((c) {
      if (_onlyMissing && c.hasCard) return false;
      return term.isEmpty || c.productName.toLowerCase().contains(term);
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          MessageBanner(_message, onClose: () => setState(() => _message = null)),
          SectionCard(
            title: 'Бэлтгэх заавар',
            subtitle: 'Бараа тус бүрийн орц ба бэлтгэх дараалал — үйлдвэрлэл бүртгэхэд орц нь автоматаар хасагдана',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Бараа хайх…'),
                  onChanged: (v) => setState(() => _search = v),
                ),
                CheckboxListTile(
                  value: _onlyMissing,
                  onChanged: (v) => setState(() => _onlyMissing = v ?? false),
                  title: const Text('Зөвхөн карт үүсээгүй'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                if (cards == null)
                  const LoadingState('Ачаалж байна…')
                else if (rows.isEmpty)
                  const EmptyState('Бараа олдсонгүй.')
                else
                  for (final card in rows) _cardTile(card),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTile(TechCard card) {
    final editing = _draft?.productId == card.productId;
    return ExpandTile(
      key: ValueKey('card:${card.productId}'),
      open: _open.contains(card.productId) || editing,
      onToggle: (open) => setState(() => open ? _open.add(card.productId) : _open.remove(card.productId)),
      tint: card.hasCard ? null : const Color(0xFFFFFBF0),
      title: Text(card.productName),
      subtitle: Text(
        card.hasCard ? '${card.items.length} орц · ${card.steps.length} алхам' : 'карт үүсээгүй',
        style: TextStyle(fontSize: 12.5, color: card.hasCard ? AppColors.muted : AppColors.warning),
      ),
      children: [editing ? _editView() : _readView(card)],
    );
  }

  Widget _blockTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted, fontSize: 13),
    ),
  );

  Widget _readView(TechCard card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _blockTitle('Нэг ширхэгт ногдох орц'),
        if (card.items.isEmpty)
          const Text('Орц бичигдээгүй — үйлдвэрлэхэд юу ч хасагдахгүй.', style: TextStyle(color: AppColors.muted))
        else
          for (final i in card.items)
            AccRow(
              i.materialName,
              Text('${formatAmount(i.qty)} ${i.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        _blockTitle('Бэлтгэх дараалал'),
        if (card.steps.isEmpty)
          const Text('Бэлтгэх дараалал бичигдээгүй байна.', style: TextStyle(color: AppColors.muted))
        else
          for (final (i, s) in card.steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(child: Text(s)),
                ],
              ),
            ),
        if (card.note != null) ...[
          const SizedBox(height: 6),
          Text(
            card.note!,
            style: const TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _draft == null ? () => _startEdit(card) : null, child: const Text('Засах')),
        ),
      ],
    );
  }

  Widget _editView() {
    final draft = _draft!;
    final materials = widget.stock.data?.materials ?? const <StockRow>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _blockTitle('Нэг ширхэгт ногдох орц'),
        if (draft.items.isEmpty) const Text('Орц алга.', style: TextStyle(color: AppColors.muted)),
        for (final (index, item) in draft.items.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: materials.any((m) => m.id == item.materialId) ? item.materialId : null,
                    isExpanded: true,
                    hint: const Text('— материал сонгох —'),
                    items: [
                      for (final m in materials)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.name} (${m.unit ?? ''})', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => item.materialId = v ?? ''),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 76,
                  child: TextField(
                    controller: item.qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: 'Тоо'),
                  ),
                ),
                IconButton(
                  tooltip: 'Хасах',
                  icon: const Icon(Icons.close, color: AppColors.danger),
                  onPressed: () => setState(() => draft.items.removeAt(index).qty.dispose()),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => draft.items.add(_DraftItem('', ''))),
            icon: const Icon(Icons.add),
            label: const Text('Орц нэмэх'),
          ),
        ),
        _blockTitle('Бэлтгэх дараалал'),
        if (draft.steps.isEmpty) const Text('Алхам алга.', style: TextStyle(color: AppColors.muted)),
        for (final (index, step) in draft.steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${index + 1}.', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Expanded(child: TextField(controller: step, minLines: 1, maxLines: 4)),
                IconButton(
                  tooltip: 'Дээш',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: index == 0
                      ? null
                      : () => setState(() {
                          final moved = draft.steps.removeAt(index);
                          draft.steps.insert(index - 1, moved);
                        }),
                ),
                IconButton(
                  tooltip: 'Хасах',
                  icon: const Icon(Icons.close, color: AppColors.danger),
                  onPressed: () => setState(() => draft.steps.removeAt(index).dispose()),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => draft.steps.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Алхам нэмэх'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _saving ? null : _cancel, child: const Text('Болих')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Хадгалж байна…' : 'Хадгалах')),
          ],
        ),
      ],
    );
  }
}
