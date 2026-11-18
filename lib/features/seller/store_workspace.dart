import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/links.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../printing/order_receipt.dart';
import 'seller_controller.dart';
import 'seller_logic.dart';
import 'seller_widgets.dart';
import 'store_picker.dart' show StoreImage;
import 'store_sheets.dart';

enum StoreTab { newOrder, balance, noOrder, orders, returns }

const _tabLabels = {
  StoreTab.newOrder: 'Захиалга бүртгэх',
  StoreTab.balance: 'Авлагын үлдэгдлийн түүх',
  StoreTab.noOrder: 'Захиалга өгөөгүй шалтгаан',
  StoreTab.orders: 'Захиалгын түүх',
  StoreTab.returns: 'Буцаалтын түүх',
};

/// Сонгосон дэлгүүрийн ажлын талбар.
class StoreWorkspace extends StatefulWidget {
  final SellerController controller;
  final VoidCallback onOrderDone;
  const StoreWorkspace({super.key, required this.controller, required this.onOrderDone});

  @override
  State<StoreWorkspace> createState() => _StoreWorkspaceState();
}

class _StoreWorkspaceState extends State<StoreWorkspace> {
  StoreTab _tab = StoreTab.newOrder;
  bool _headerOpen = false;
  int? _session;

  SellerController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final store = c.selectedStore!;
        // Дэлгүүр сонгогдох бүрд (хуулах/засахад ч) header хаалттай, таб «Захиалга бүртгэх» руу.
        if (_session != c.storeSession) {
          _session = c.storeSession;
          _headerOpen = false;
          _tab = StoreTab.newOrder;
        }
        return Column(
          children: [
            _header(store),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final t in StoreTab.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_tabLabels[t]!),
                        selected: _tab == t,
                        onSelected: (_) => setState(() => _tab = t),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                StoreTab.newOrder => PosPanel(controller: c, onOrderDone: widget.onOrderDone),
                StoreTab.balance => _BalanceTab(key: ValueKey('bal:${store['id']}'), controller: c),
                StoreTab.noOrder => _NoOrderTab(key: ValueKey('no:${store['id']}'), controller: c),
                StoreTab.orders => _StoreOrdersTab(controller: c, onOrderDone: widget.onOrderDone),
                StoreTab.returns => _StoreReturnsTab(key: ValueKey('ret:${store['id']}'), controller: c),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _header(Json store) {
    return Material(
      color: AppColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: Row(
              children: [
                IconButton(tooltip: 'Дэлгүүрүүд', icon: const Icon(Icons.arrow_back), onPressed: c.leaveStore),
                StoreImage(url: str(store['coverImageUrl']), size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _headerOpen = !_headerOpen),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${store['name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            Tag('#${str(store['storeCode']) ?? '-'}'),
                            if (str(store['zone']) != null)
                              Tag('Бүс: ${store['zone']}', color: AppColors.brand, background: const Color(0xFFE7F3EE)),
                            // Аль үнийн шатлалаар захиалга авч байгааг ил харуулна.
                            if (store['storeType'] == 'wholesale') const Tag.warning('Бөөний үнэ'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _headerOpen ? 'Хураах' : 'Дэлгэрэнгүй',
                  icon: Icon(_headerOpen ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _headerOpen = !_headerOpen),
                ),
              ],
            ),
          ),
          if (_headerOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.call_outlined, size: 16),
                    label: Text(str(store['phone']) ?? '—'),
                    onPressed: str(store['phone']) == null ? null : () => callPhone(str(store['phone'])),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.place_outlined, size: 16),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(str(store['address']) ?? '—', overflow: TextOverflow.ellipsis),
                    ),
                    onPressed: () => openDirections(str(store['location']), str(store['address'])),
                  ),
                  Chip(
                    avatar: const Icon(Icons.person_outline, size: 16),
                    label: Text(str(store['contactName']) ?? '—'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.info_outline, size: 16),
                    label: const Text('Дэлгэрэнгүй мэдээлэл'),
                    onPressed: () => openCustomerDetail(context, c, '${store['id']}'),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

// ── POS ─────────────────────────────────────────────────────────────────────
class PosPanel extends StatefulWidget {
  final SellerController controller;
  final VoidCallback onOrderDone;
  const PosPanel({super.key, required this.controller, required this.onOrderDone});

  @override
  State<PosPanel> createState() => _PosPanelState();
}

class _PosPanelState extends State<PosPanel> {
  String _query = '';
  String _category = '';
  bool _sending = false;
  final _scroll = ScrollController();
  final _cartKey = GlobalKey();
  late final _noteController = TextEditingController(text: widget.controller.note);

  SellerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_syncNote);
  }

  @override
  void dispose() {
    c.removeListener(_syncNote);
    _scroll.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ⚠ Тайлбар гаднаас солигдоно (засварт ачаалах, болих, дэлгүүр солих) —
  //   талбарыг дагуулахгүй бол хуучин тайлбар нуугдаж, хадгалахад хоосроно.
  void _syncNote() {
    if (_noteController.text != c.note) _noteController.text = c.note;
  }

  void _error(String text) {
    c.setMessage(AppMessage.error(text));
    alertError(context, text);
  }

  Future<void> _openProduct(Json product) async {
    if (c.catalogLocked) return; // хуваарийн түгжээ
    final fields = unitFields(product, c.selectedStore);
    final result = await showModalBottomSheet<({int pieces, int packs})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QtySheet(
        name: '${product['name'] ?? ''}',
        unitPrice: priceOf(product, c.selectedStore),
        unit: str(product['unit']) ?? 'ширхэг',
        dual: fields.pack,
        allowPiece: fields.piece,
        packSize: packSizeOf(product) ?? 0,
        actionLabel: 'Сагсанд нэмэх',
      ),
    );
    if (result == null) return;
    final id = '${product['id']}';
    if (fields.pack) {
      // ⚠ Хоёулаа хоосон бол ЮУ Ч нэмэхгүй — санаагүй мөр чимээгүй орохоос сэргийлнэ.
      if (result.pieces <= 0 && result.packs <= 0) {
        _error('Ширхэг эсвэл багцын тоо оруулна уу.');
        return;
      }
      if (result.pieces > 0) c.addProduct(id, result.pieces);
      if (result.packs > 0) c.addProduct(id, result.packs, pack: true);
    } else {
      c.addProduct(id, result.pieces);
    }
  }

  Future<void> _openReturn(int index) async {
    if (c.catalogLocked) return;
    final p = c.returnProducts[index];
    // ⚠ Буцаалт ҮРГЭЛЖ ШИРХЭГЭЭР — багцын мөргүй.
    final result = await showModalBottomSheet<({int pieces, int packs})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QtySheet(
        name: '${p['name'] ?? ''}',
        unitPrice: toNum(p['unitPrice']),
        unit: str(p['unit']) ?? 'ширхэг',
        subtitle: 'боломж ${toInt(p['availableQty'])} ш',
        dual: false,
        allowPiece: true,
        packSize: 0,
        actionLabel: 'Буцаалтад нэмэх',
      ),
    );
    if (result == null) return;
    final err = c.addReturn(index, result.pieces);
    if (err != null) _error(err);
  }

  Future<void> _submit() async {
    final invalid = c.validateOrder();
    if (invalid != null) {
      _error(invalid);
      return;
    }
    final store = c.selectedStore!;
    final editing = c.editingOrder;
    final ok = await confirmDialog(
      context,
      title: editing != null ? 'Өөрчлөлт хадгалах' : 'Захиалга баталгаажуулах',
      message: editing != null
          ? '№${shortId(editing.id)} захиалгын өөрчлөлтийг хадгалах уу?'
          : '${store['name']} дэлгүүрийн захиалгыг баталгаажуулах уу?',
      confirmLabel: editing != null ? 'Хадгалах' : 'Баталгаажуулах',
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      c.note = _noteController.text;
      final id = await c.submitOrder();
      _noteController.clear();
      // Захиалга дууссан — «Захиалга» хуудас руу шилжиж баримтыг нээнэ.
      c.setMessage(
        AppMessage.success(
          editing != null
              ? 'Захиалга шинэчлэгдлээ. Баримтаа хэвлэнэ үү.'
              : 'Захиалга баталгаажлаа. Баримтаа хэвлэнэ үү.',
        ),
      );
      widget.onOrderDone();
      if (id.isNotEmpty && mounted) await OrderReceiptScreen.open(context, c.api, id);
    } catch (e) {
      _error(
        SellerController.errorText(
          e,
          editing != null ? 'Захиалга шинэчлэхэд алдаа гарлаа.' : 'Захиалга бүртгэхэд алдаа гарлаа.',
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = c.selectedStore;
    final locked = c.catalogLocked;
    final returnMode = _category == returnCategory;
    final cats = categoryOptions(c.products);
    if (_category.isNotEmpty && !returnMode && !cats.any((e) => e.$1 == _category)) _category = '';
    if (returnMode && c.returnProducts.isEmpty) _category = '';
    final products = filterProducts(c.products, store, query: _query, category: returnMode ? '' : _category);
    final lines = c.cart.entries.toList();
    final net = c.orderTotal - c.returnTotal;
    final cartCount = linesPieces(c.cart.values);

    return Stack(
      children: [
        ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
          children: [
            MessageBanner(c.message, onClose: () => c.setMessage(null)),
            if (c.editingOrder != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Захиалга №${shortId(c.editingOrder!.id)} засаж байна',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      // Web-тэй адил засвар болиход «Захиалга» хуудас руу буцна.
                      onPressed: () {
                        c.cancelEdit();
                        widget.onOrderDone();
                      },
                      child: const Text('Болих'),
                    ),
                  ],
                ),
              ),
            SearchField(hint: 'Бараа хайх…', onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ангилал'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Бүх ангилал')),
                // «Буцаах бараа» нь буцаах боломжтой бараа байгаа үед л — амархан олдохын тулд эхэнд.
                if (c.returnProducts.isNotEmpty)
                  const DropdownMenuItem(value: returnCategory, child: Text('Буцаах бараа')),
                for (final (key, name) in cats) DropdownMenuItem(value: key, child: Text(name)),
              ],
              onChanged: (v) => setState(() => _category = v ?? ''),
            ),
            const SizedBox(height: 10),
            if (locked)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: const Color(0xFFF1F4F9), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    const Icon(Icons.lock_outline, color: AppColors.muted),
                    const SizedBox(height: 4),
                    const Text('Өнөөдөр захиалга авахгүй', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      scheduleLockText(store!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            Opacity(
              opacity: locked ? 0.35 : 1,
              child: IgnorePointer(ignoring: locked, child: returnMode ? _returnCatalog(context) : _catalog(products)),
            ),
            const SizedBox(height: 16),
            KeyedSubtree(key: _cartKey, child: _cart(lines, net)),
          ],
        ),
        // Сагс руу очих хөвөгч товч — сагсанд бараа байгаа үед.
        if (lines.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                final ctx = _cartKey.currentContext;
                if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
              },
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('Сагс харах · $cartCount'),
                  const Spacer(),
                  Text(formatMoney(c.orderTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _catalog(List<Json> products) {
    if (!c.loaded && c.products.isEmpty) return const LoadingState('Бараа ачаалж байна…');
    if (products.isEmpty) return const EmptyState('Бараа олдсонгүй.');
    final store = c.selectedStore;
    return Column(
      children: [
        for (final p in products)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              onTap: () => _openProduct(p),
              leading: _ProductImage(url: str(p['imageUrl'])),
              title: Text('${p['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${str(p['productCode']) ?? '-'} · ${str(p['categoryName']) ?? 'Ангилалгүй'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  Text('${formatMoney(priceOf(p, store))} / ${str(p['unit']) ?? 'ширхэг'}'),
                  // ⚠ Багцын НИЙТ дүн нь ширхэгийн үнээс гардаг тул сагсны дүнтэй үргэлж таарна.
                  if (unitFields(p, store).pack)
                    Text(
                      '${packLabel(p['packSize'])} · ${formatMoney(packPriceOf(p, store))}',
                      style: const TextStyle(fontSize: 12, color: AppColors.brand),
                    ),
                ],
              ),
              trailing: const Icon(Icons.add_circle_outline, color: AppColors.brand),
            ),
          ),
      ],
    );
  }

  Widget _returnCatalog(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = [
      for (var i = 0; i < c.returnProducts.length; i++)
        if (q.isEmpty ||
            '${c.returnProducts[i]['name'] ?? ''} ${c.returnProducts[i]['barcode'] ?? ''}'.toLowerCase().contains(q))
          i,
    ];
    final orderTotal = c.orderTotal;
    final room = c.returnRoomLeft;
    final closed = c.returnMaxPercent <= 0;
    final noOrder = orderTotal <= 0;
    // Бодлогын мөр ҮРГЭЛЖ харагдана — хязгаартаа мөргөхөөс өмнө мэдэж байна.
    final window = c.returnWindowDays != null
        ? 'сүүлийн ${c.returnWindowDays} хоногт хүргэгдсэн бараа'
        : 'хугацааны хязгааргүй';
    final policy = [if (c.returnMaxPercent < 100) 'захиалгын дүнгийн ${c.returnMaxPercent}%', window].join(' · ');
    final note = closed
        ? 'Буцаалт түр хаалттай байна. Админаас хязгаарыг нээлгэнэ үү.'
        : noOrder
        ? 'Эхлээд бараа захиалж, дараа нь буцаалт нэмнэ.'
        : room <= 0
        ? 'Буцаалтын дүн хязгаартаа (${formatMoney(c.returnCapAmount)}) хүрсэн байна.'
        : 'Үлдсэн боломж: ${formatMoney(room)} (нийт ${formatMoney(c.returnCapAmount)})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Буцаалтын нөхцөл: $policy', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        Text(note, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          EmptyState(c.returnProducts.isNotEmpty ? 'Хайлтад тохирох бараа алга.' : 'Хүргэгдсэн бараа алга.')
        else
          for (final i in items)
            () {
              final p = c.returnProducts[i];
              final price = toNum(p['unitPrice']);
              // Энэ барааны нэг ш ч багтахгүй бол идэвхгүй.
              final capped = noOrder || closed || price > room;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  enabled: !capped,
                  onTap: capped ? null : () => _openReturn(i),
                  title: Text('${p['name'] ?? ''}'),
                  subtitle: Text(
                    'Буцаах боломж: ${toInt(p['availableQty'])} ш · ${formatMoney(price)} / ${str(p['unit']) ?? 'ширхэг'}',
                  ),
                  trailing: Icon(Icons.undo, color: capped ? AppColors.border : AppColors.warning),
                ),
              );
            }(),
      ],
    );
  }

  Widget _cart(List<MapEntry<String, CartLine>> lines, num net) {
    final returns = c.returnCart.entries.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Захиалгын сагс', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                if (lines.isNotEmpty || returns.isNotEmpty)
                  TextButton(onPressed: c.clearCart, child: const Text('Цэвэрлэх')),
              ],
            ),
            Text('${c.selectedStore?['name'] ?? ''}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            if (lines.isEmpty)
              const EmptyState('Сагс хоосон байна. Бараанаас сонгож сагсандаа нэмнэ үү.')
            else
              for (final e in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              '${formatMoney(e.value.unitPrice)} / ${e.value.unit}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => c.stepCart(e.key, -1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${e.value.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => c.stepCart(e.key, 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          formatMoney(e.value.lineTotal),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Хасах',
                        onPressed: () => c.removeCart(e.key),
                        icon: const Icon(Icons.close, size: 18, color: AppColors.danger),
                      ),
                    ],
                  ),
                ),
            const Divider(),
            AccRow('Барааны төрөл', Text('${lines.length}')),
            AccRow('Нийт тоо', Text('${linesPieces(c.cart.values)}')),
            AccRow('Захиалгын дүн', Text(formatMoney(c.orderTotal))),
            AccRow('Буцаалт (−)', Text(formatMoney(c.returnTotal))),
            AccRow(
              'Төлөх дүн',
              Text(
                formatMoney(net),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: net < 0 ? AppColors.danger : AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Буцаах бараа (заавал биш)', style: TextStyle(fontWeight: FontWeight.w600)),
            if (returns.isEmpty)
              const Text(
                '«Ангилал» → «Буцаах бараа»-аас нэмнэ.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              )
            else
              for (final e in returns)
                Row(
                  children: [
                    Expanded(child: Text(e.value.name)),
                    Text(
                      '${e.value.qty} × ${formatMoney(e.value.unitPrice)}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(width: 8),
                    Text(formatMoney(e.value.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => c.removeReturn(e.key),
                      icon: const Icon(Icons.close, size: 18, color: AppColors.danger),
                    ),
                  ],
                ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Захиалгын тайлбар',
                hintText: 'Шаардлагатай бол тайлбар бичнэ',
              ),
              onChanged: (v) => c.note = v,
            ),
            const SizedBox(height: 12),
            FilledButton(
              // Сөрөг төлөх дүнтэй захиалга байж болохгүй.
              onPressed: _sending || net < 0 ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(
                _sending
                    ? 'Илгээж байна…'
                    : c.editingOrder != null
                    ? 'Өөрчлөлтийг хадгалах'
                    : 'Баталгаажуулж баримт гаргах',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String? url;
  const _ProductImage({this.url});

  @override
  Widget build(BuildContext context) {
    const placeholder = SizedBox(
      width: 44,
      height: 44,
      child: Icon(Icons.inventory_2_outlined, color: AppColors.muted),
    );
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(url!, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}

/// Тоо оруулах sheet. ⚠ Хоёр нэгжтэй (dual) үед 0-ээс эхэлнэ, ганц нэгжид 1-ээс.
class _QtySheet extends StatefulWidget {
  final String name;
  final num unitPrice;
  final String unit;
  final String? subtitle;
  final bool dual;
  final bool allowPiece;
  final int packSize;
  final String actionLabel;

  const _QtySheet({
    required this.name,
    required this.unitPrice,
    required this.unit,
    required this.dual,
    required this.allowPiece,
    required this.packSize,
    required this.actionLabel,
    this.subtitle,
  });

  @override
  State<_QtySheet> createState() => _QtySheetState();
}

class _QtySheetState extends State<_QtySheet> {
  late int _pieces = widget.dual ? 0 : 1;
  int _packs = 0;

  @override
  Widget build(BuildContext context) {
    // ⚠ Үнэ ҮРГЭЛЖ нэг ширхэгийнх — багц бол зөвхөн тооны хурдавчлал.
    final total = (_pieces + _packs * widget.packSize) * widget.unitPrice;
    final showPiece = !widget.dual || widget.allowPiece;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              [
                '${formatMoney(widget.unitPrice)} / ${widget.unit}',
                if (widget.dual) '${packLabel(widget.packSize)} = ${formatMoney(widget.unitPrice * widget.packSize)}',
                ?widget.subtitle,
              ].join(' · '),
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            if (showPiece)
              Center(
                child: QtyStepper(
                  label: widget.dual ? unitPieceWord : null,
                  value: _pieces,
                  floor: widget.dual ? 0 : 1,
                  onChanged: (v) => setState(() => _pieces = v),
                ),
              ),
            if (widget.dual) ...[
              const SizedBox(height: 8),
              Center(
                child: QtyStepper(
                  label: unitPack,
                  value: _packs,
                  floor: 0,
                  onChanged: (v) => setState(() => _packs = v),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.of(context).pop((pieces: _pieces, packs: _packs)),
              child: Text('${widget.actionLabel} · ${formatMoney(total)}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Авлагын үлдэгдлийн түүх ─────────────────────────────────────────────────
class _BalanceTab extends StatefulWidget {
  final SellerController controller;
  const _BalanceTab({super.key, required this.controller});

  @override
  State<_BalanceTab> createState() => _BalanceTabState();
}

class _BalanceTabState extends State<_BalanceTab> {
  Json? _balance;
  List<Json> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.controller;
    final store = c.selectedStore!;
    try {
      _payments = jsonList(await c.api.get('/store-payments', query: {'storeId': '${store['id']}'}));
    } catch (_) {
      _payments = [];
    }
    try {
      final b = await c.api.get('/stores/${store['id']}/balance');
      _balance = b is Json ? b : null;
    } catch (_) {
      _balance = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final store = c.selectedStore!;
    // Зээлээр (эсвэл хэсэгчлэн зээлээр) хүргэсэн захиалгууд — авлага үүсгэсэн нь.
    final creditOrders = c.orders.where(
      (o) => o['storeId'] == store['id'] && o['status'] == 'delivered' && toNum(o['creditAmount']) > 0,
    );
    const methodLabel = {'cash': 'Бэлэн', 'transfer': 'Данс', 'credit': 'Зээл'};
    final moves = [
      for (final o in creditOrders)
        (
          at: o['createdAt'],
          type: 'Зээлээр хүргэлт',
          detail: '#${shortId(o['id']).toLowerCase()}',
          amount: toNum(o['creditAmount']),
          charge: true,
        ),
      for (final p in _payments)
        (
          at: p['createdAt'],
          type: 'Төлбөр',
          detail: '${methodLabel[p['method']] ?? p['method'] ?? ''}${str(p['note']) != null ? ' · ${p['note']}' : ''}',
          amount: toNum(p['amount']),
          charge: false,
        ),
    ]..sort((a, b) => (parseDate(b.at) ?? DateTime(0)).compareTo(parseDate(a.at) ?? DateTime(0)));
    final b = _balance;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: KpiTile(
                  label: 'Зээлийн эрх',
                  value: b == null
                      ? formatMoney(toNum(store['creditLimit']))
                      : (b['creditLimit'] != null && toNum(b['creditLimit']) > 0
                            ? formatMoney(toNum(b['effectiveLimit']))
                            : 'Хязгааргүй'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KpiTile(label: 'Нийт авсан зээл', value: formatMoney(toNum(b?['charges']))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          KpiTile(label: 'Нийт төлөөгүй зээл', value: formatMoney(toNum(b?['outstanding'])), accent: AppColors.danger),
          const SizedBox(height: 12),
          if (_loading)
            const LoadingState('Ачаалж байна…')
          else if (moves.isEmpty)
            const EmptyState('Хөдөлгөөн алга.')
          else
            for (final m in moves)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text(m.type),
                  subtitle: Text('${formatDateTime(m.at)} · ${m.detail}'),
                  trailing: Text(
                    '${m.charge ? '+' : '−'}${formatMoney(m.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: m.charge ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ── Захиалга өгөөгүй шалтгаан ───────────────────────────────────────────────
const List<String> noOrderReasons = [
  'Бараа хангалттай үлдэгдэлтэй',
  'Захиалга өгөх хүн алга',
  'Дэлгүүр хаалттай',
  'Өмнөх авлага төлөгдөөгүй',
  'Үнэ тохиролцоогүй',
  'Бусад',
];

class _NoOrderTab extends StatefulWidget {
  final SellerController controller;
  const _NoOrderTab({super.key, required this.controller});

  @override
  State<_NoOrderTab> createState() => _NoOrderTabState();
}

class _NoOrderTabState extends State<_NoOrderTab> {
  String _reason = noOrderReasons.first;
  final _note = TextEditingController();
  List<Json>? _rows;
  String? _loadError;
  AppMessage? _message;
  bool _saving = false;

  SellerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = jsonList(await c.api.get('/no-order-reasons', query: {'storeId': '${c.selectedStore!['id']}'}));
      if (mounted) {
        setState(() {
          _rows = rows;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = SellerController.errorText(e, 'Татахад алдаа гарлаа.'));
    }
  }

  Future<void> _save() async {
    final note = _note.text.trim();
    if (_reason == 'Бусад' && note.isEmpty) {
      setState(() => _message = const AppMessage.error('«Бусад» сонгосон бол тэмдэглэл заавал бичнэ үү.'));
      return;
    }
    // Давхар дарж давхардсан шалтгаан бүртгэхээс сэргийлнэ (GPS хүлээх хугацаанд ч).
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Геофенс: шалтгааныг дэлгүүр дээр биеэр очсон үед л.
      final coords = c.isSenior ? null : await GeoService.instance.getCoords();
      if (!mounted) return;
      if (coords == null && c.geofenceCheckOn) {
        setState(
          () => _message = const AppMessage.error(
            'Байршил тодорхойлж чадсангүй. GPS-ээ асааж, дэлгүүр дээрээ ирээд дахин оролдоно уу.',
          ),
        );
        return;
      }
      await c.api.post('/no-order-reasons', {
        'storeId': c.selectedStore!['id'],
        'reason': _reason,
        if (note.isNotEmpty) 'note': note,
        'lat': ?coords?.lat,
        'lng': ?coords?.lng,
      });
      _note.clear();
      if (!mounted) return;
      setState(() => _message = const AppMessage.success('Шалтгаан бүртгэгдлээ.'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = AppMessage.error(SellerController.errorText(e, 'Шалтгаан бүртгэхэд алдаа гарлаа.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        const Text(
          'Дэлгүүрт зочилсон ч захиалга аваагүй бол шалтгааныг бүртгэнэ',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        MessageBanner(_message),
        DropdownButtonFormField<String>(
          initialValue: _reason,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Шалтгаан'),
          items: [for (final r in noOrderReasons) DropdownMenuItem(value: r, child: Text(r))],
          onChanged: (v) => setState(() => _reason = v ?? noOrderReasons.first),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Тэмдэглэл', hintText: '«Бусад» бол энд бичнэ / нэмэлт тайлбар'),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Бүртгэж байна…' : 'Шалтгаан бүртгэх')),
        const SizedBox(height: 16),
        if (_loadError != null)
          EmptyState(_loadError!)
        else if (rows == null)
          const LoadingState('Ачаалж байна…')
        else if (rows.isEmpty)
          const EmptyState('Бүртгэл алга.')
        else
          for (final r in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text('${r['reason'] ?? ''}'),
                subtitle: Text('${formatDateTime(r['createdAt'])} · ${str(r['note']) ?? '-'}'),
              ),
            ),
      ],
    );
  }
}

// ── Дэлгүүрийн захиалгын түүх ───────────────────────────────────────────────
class _StoreOrdersTab extends StatelessWidget {
  final SellerController controller;
  final VoidCallback onOrderDone;
  const _StoreOrdersTab({required this.controller, required this.onOrderDone});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final list = c.orders.where((o) => o['storeId'] == c.selectedStore!['id']).toList();
    if (list.isEmpty) return const EmptyState('Захиалгын түүх байхгүй.');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        for (final o in list)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('№${shortId(o['id'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              formatDateTime(o['createdAt']),
                              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMoney(orderPayable(o)), style: const TextStyle(fontWeight: FontWeight.w700)),
                          statusTag(o['status']),
                        ],
                      ),
                    ],
                  ),
                  if (toNum(o['discountAmount']) > 0)
                    Text(
                      'Барааны дүн ${formatMoney(toNum(o['totalAmount']))} · Урамшуулал −${formatMoney(toNum(o['discountAmount']))}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      OutlinedButton(
                        onPressed: () => OrderReceiptScreen.open(context, c.api, '${o['id']}'),
                        child: const Text('Баримт'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          try {
                            final err = await c.openOrderInCart('${o['id']}', edit: false);
                            if (err != null && context.mounted) alertError(context, err);
                          } catch (e) {
                            if (context.mounted) {
                              alertError(context, SellerController.errorText(e, 'Захиалга ачаалахад алдаа гарлаа.'));
                            }
                          }
                        },
                        child: const Text('Хуулах'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Дэлгүүрийн буцаалтын түүх ───────────────────────────────────────────────
class _StoreReturnsTab extends StatefulWidget {
  final SellerController controller;
  const _StoreReturnsTab({super.key, required this.controller});

  @override
  State<_StoreReturnsTab> createState() => _StoreReturnsTabState();
}

class _StoreReturnsTabState extends State<_StoreReturnsTab> {
  List<Json>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.controller;
    try {
      final rows = jsonList(await c.api.get('/orders/store-return-items/${c.selectedStore!['id']}'));
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = SellerController.errorText(e, 'Татахад алдаа гарлаа.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (_error != null) return EmptyState(_error!);
    if (rows == null) return const LoadingState('Ачаалж байна…');
    if (rows.isEmpty) return const EmptyState('Буцаалт алга.');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [for (final r in rows) ReturnItemCard(row: r)],
    );
  }
}

class ReturnItemCard extends StatelessWidget {
  final Json row;
  final bool showStore;
  const ReturnItemCard({super.key, required this.row, this.showStore = false});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      title: Text(showStore ? '${row['storeName'] ?? '-'}' : '${row['productName'] ?? '-'}'),
      subtitle: Text(
        [
          if (showStore) '${row['productName'] ?? '-'}',
          '№${shortId(row['orderId']).toLowerCase()}',
          formatDateTime(row['createdAt']),
          'Баркод ${str(row['barcode']) ?? '-'}',
          '${row['qty']} ш',
        ].join(' · '),
      ),
      trailing: Text(formatMoney(toNum(row['lineTotal'])), style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}
