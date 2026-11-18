import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/ui.dart';
import '../../printing/order_receipt.dart';
import 'delivery_controller.dart';
import 'delivery_logic.dart';

class DeliveryOrdersTab extends StatefulWidget {
  final DeliveryController controller;
  const DeliveryOrdersTab({super.key, required this.controller});

  @override
  State<DeliveryOrdersTab> createState() => _DeliveryOrdersTabState();
}

class _DeliveryOrdersTabState extends State<DeliveryOrdersTab> {
  String _search = '';
  final Set<String> _open = {};

  DeliveryController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final searching = _search.trim().isNotEmpty;
        // Хайлт + маршрутын дараалал: одоогийн байршлаас ойрын дэлгүүр эхэнд.
        final ordered = optimizeRoute(c.assigned.where((o) => matchesSearch(o, _search)).toList(), c.myCoords);
        final showRouteBadge = !searching && c.myCoords != null && ordered.length > 1;
        return RefreshIndicator(
          onRefresh: c.loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              MessageBanner(c.message, onClose: () => c.setMessage(null)),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Дэлгүүр, хаяг, утсаар хайх…'),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              if (c.loading && !c.loadedOnce)
                const LoadingState('Захиалгуудыг ачаалж байна…')
              else if (ordered.isEmpty)
                // Жагсаалт нь ЗӨВХӨН үйлдвэрээс хүлээлгэж өгсөн захиалгыг агуулдаг тул
                // хоосон нь «захиалга алга» гэсэн үг биш байж болно — шалтгааныг хэлнэ.
                EmptyState(searching
                    ? 'Хайлтад тохирох захиалга алга.'
                    : 'Танд хүлээлгэж өгсөн захиалга алга. Үйлдвэр бараагаа өгмөгц энд гарна.')
              else
                for (final (i, o) in ordered.indexed)
                  _OrderCard(
                    order: o,
                    controller: c,
                    first: showRouteBadge && i == 0,
                    open: _open.contains(o.id),
                    onToggle: () => setState(() => _open.contains(o.id) ? _open.remove(o.id) : _open.add(o.id)),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final DeliveryOrder order;
  final DeliveryController controller;
  final bool first;
  final bool open;
  final VoidCallback onToggle;

  const _OrderCard({required this.order, required this.controller, required this.first, required this.open, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final nav = directionsUri(o.location, o.address);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (first) ...[
                          const Tag('Эхлээд очих', color: AppColors.brand, background: Color(0xFFE7F3EE)),
                          const SizedBox(height: 4),
                        ],
                        Text(o.storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                        if (o.isOnline || !o.isHandedOver) ...[
                          const SizedBox(height: 4),
                          Wrap(spacing: 4, runSpacing: 4, children: [
                            // akifoods.mn-ээс ирсэн, урьдчилж төлөгдсөн — мөнгө авахгүй.
                            if (o.isOnline) const Tag('Онлайн · Төлсөн', color: Color(0xFF2F6FED), background: Color(0xFFE8F0FF)),
                            // Үйлдвэрээс хүлээлгэж өгөөгүй — хориг биш, мэдээлэл.
                            if (!o.isHandedOver) const Tag.warning('Үйлдвэрээс аваагүй'),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  Text(formatMoney(o.totalAmount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(o.address ?? (nav != null ? 'Байршил харах' : 'Байршил бүртгэгдээгүй')),
                    trailing: nav == null ? null : const Icon(Icons.navigation_outlined, color: AppColors.brand),
                    onTap: nav == null ? null : () => openDirections(o.location, o.address),
                  ),
                  if (o.phone != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.phone_outlined),
                      title: Text(o.phone!),
                      onTap: () => callPhone(o.phone),
                    ),
                  if (o.sellerName != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text('${o.sellerName}${o.sellerPhone != null ? ' · ${o.sellerPhone}' : ''}'),
                      onTap: o.sellerPhone == null ? null : () => callPhone(o.sellerPhone),
                    ),
                  if (o.items.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.list_alt_outlined),
                      title: Text('Захиалгын задаргаа (${o.items.length})'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showItemsSheet(context, o),
                    ),
                  const SizedBox(height: 4),
                  if (o.isActive)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => OrderReceiptScreen.open(context, controller.api, o.id),
                            child: const Text('Баримт'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(onPressed: () => showEditItemsSheet(context, controller, o), child: const Text('Засах')),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          // Онлайн захиалганд ТООЦОО ГЭЖ БАЙХГҮЙ — ганц үйлдэл: хүлээлгэж өглөө.
                          child: FilledButton(
                            onPressed: () => o.isOnline
                                ? _deliverOnline(context, controller, o)
                                : showSettlementSheet(context, controller, o),
                            child: Text(o.isOnline ? 'Хүргэсэн' : 'Тооцоо авах'),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _deliverOnline(BuildContext context, DeliveryController c, DeliveryOrder o) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Хүргэсэн гэж бүртгэх'),
      content: Text('${o.raw['customerName'] ?? o.storeName} — барааг хүлээлгэн өглөө үү? Төлбөр нь аль хэдийн төлөгдсөн тул мөнгө авахгүй.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Болих')),
        FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Хүргэсэн')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await c.deliverOnline(o);
    c.setMessage(const AppMessage.success('Хүргэлт бүртгэгдлээ.'));
    if (context.mounted) await OrderReceiptScreen.open(context, c.api, o.id);
  } catch (e) {
    c.setMessage(AppMessage.error(e is ApiException ? e.message : 'Хүргэлт бүртгэхэд алдаа гарлаа.'));
  }
}

// ── Захиалгын задаргаа ──────────────────────────────────────────────────────
Future<void> showItemsSheet(BuildContext context, DeliveryOrder o) {
  final items = sortItemsByCategory(o.items);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const Text('Захиалгын задаргаа', style: TextStyle(color: AppColors.muted)),
          Text(o.storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 8),
          for (final item in items)
            () {
              final qty = toNum(item['qty']);
              final line = toNum(item['lineTotal']);
              // Нэгжийн үнэ — мөрийн дүн ÷ тоо (бүхлээр хуваагдвал).
              final unit = qty > 0 && line % qty == 0 ? line / qty : null;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(6)),
                    child: Text('${formatAmount(qty)} ш', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${item['name'] ?? ''}'),
                      if (unit != null) Text('нэгж ${formatMoney(unit)}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ]),
                  ),
                  Text(formatMoney(line), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              );
            }(),
          const Divider(),
          Row(children: [
            const Expanded(child: Text('Нийт дүн', style: TextStyle(fontWeight: FontWeight.w700))),
            Text(formatMoney(o.totalAmount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ],
      ),
    ),
  );
}

// ── Барааны засвар (тоо бууруулах / мөр хасах) ──────────────────────────────
class _EditRow {
  final String id;
  final String name;
  final int origQty;
  final num unitPrice;
  int qty;
  bool removed = false;
  _EditRow(this.id, this.name, this.origQty, this.unitPrice) : qty = origQty;
}

Future<void> showEditItemsSheet(BuildContext context, DeliveryController c, DeliveryOrder o) {
  // Засах цонх ч баримттай ИЖИЛ дараалалтай — мөр мөрөөрөө таарна.
  final items = sortItemsByCategory(o.items);
  if (items.isEmpty || items.first['id'] == null) {
    c.setMessage(const AppMessage.error('Барааны мэдээлэл дутуу байна — жагсаалтаа шинэчилнэ үү.'));
    return Future.value();
  }
  final rows = [
    for (final i in items) _EditRow('${i['id']}', '${i['name'] ?? ''}', toInt(i['qty']), toNum(i['unitPrice'])),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _EditItemsSheet(controller: c, order: o, rows: rows),
  );
}

class _EditItemsSheet extends StatefulWidget {
  final DeliveryController controller;
  final DeliveryOrder order;
  final List<_EditRow> rows;
  const _EditItemsSheet({required this.controller, required this.order, required this.rows});

  @override
  State<_EditItemsSheet> createState() => _EditItemsSheetState();
}

class _EditItemsSheetState extends State<_EditItemsSheet> {
  bool _busy = false;
  String? _error;

  List<_EditRow> get rows => widget.rows;

  Future<void> _save() async {
    final kept = rows.where((r) => !r.removed).toList();
    final summary = [
      for (final r in rows.where((r) => r.removed)) '${r.name} — хасагдана',
      for (final r in kept.where((r) => r.qty != r.origQty)) '${r.name} (${r.origQty}→${r.qty})',
    ].join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Захиалгын засвар хадгалах'),
        content: Text('Өөрчлөлт: $summary. Хадгалах уу? Захиалгын дүн шинэчлэгдэнэ.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Болих')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Хадгалах')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.controller.saveItems(widget.order, [for (final r in kept) (r.id, r.qty)]);
      widget.controller.setMessage(const AppMessage.success('Захиалгын бараа шинэчлэгдлээ.'));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Засвар хадгалахад алдаа гарлаа.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _returnOrder() async {
    final values = await showPromptDialog(
      context,
      title: 'Захиалга буцаах',
      message: 'Энэ захиалга бүхэлдээ буруу бол буцаана. Шалтгаанаа бичнэ үү.',
      fields: const [PromptField('reason', 'Шалтгаан', required: true)],
      confirmLabel: 'Буцаах',
    );
    final reason = values?['reason'] ?? '';
    if (reason.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Геофенс: буцаахад мөн дэлгүүр дээр байх шаардлагатай (сервер шалгана).
      await widget.controller.returnOrder(widget.order, reason);
      widget.controller.setMessage(const AppMessage.success('Захиалга буцаагдлаа — шалтгаан бүртгэгдсэн.'));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Буцаахад алдаа гарлаа.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = rows.where((r) => !r.removed).fold<num>(0, (s, r) => s + r.qty * r.unitPrice);
    final changed = rows.any((r) => r.removed || r.qty != r.origQty);
    final allRemoved = rows.every((r) => r.removed);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const Text('Захиалга засах', style: TextStyle(color: AppColors.muted)),
          Text(widget.order.storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 4),
          const Text(
            'Дэлгүүрийн аваагүй барааны тоог хасах эсвэл мөрийг бүрэн хасна. Шинэ бараа нэмэх, тоо өсгөх боломжгүй.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_error != null) MessageBanner(AppMessage.error(_error!)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      r.name,
                      style: TextStyle(
                        decoration: r.removed ? TextDecoration.lineThrough : null,
                        color: r.removed ? AppColors.muted : null,
                      ),
                    ),
                    Text(
                      r.removed ? 'хасагдсан' : 'нэгж ${formatMoney(r.unitPrice)} · анх ${r.origQty} ш',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ]),
                ),
                if (r.removed)
                  TextButton(
                    onPressed: () => setState(() {
                      r.removed = false;
                      r.qty = r.origQty;
                    }),
                    child: const Text('Сэргээх'),
                  )
                else ...[
                  IconButton(
                    tooltip: 'Хасах',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() => r.qty <= 1 ? r.removed = true : r.qty -= 1),
                  ),
                  SizedBox(width: 28, child: Text('${r.qty}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
                  // Тоог анхны хэмжээнээс ХЭТРҮҮЛЭХГҮЙ — машинд илүү бараа байхгүй.
                  IconButton(
                    tooltip: 'Нэмэх',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: r.qty >= r.origQty ? null : () => setState(() => r.qty += 1),
                  ),
                  IconButton(
                    tooltip: 'Мөр хасах',
                    icon: const Icon(Icons.close, color: AppColors.danger),
                    onPressed: () => setState(() => r.removed = true),
                  ),
                ],
              ]),
            ),
          const Divider(),
          Row(children: [
            const Expanded(child: Text('Шинэ барааны дүн', style: TextStyle(fontWeight: FontWeight.w700))),
            Text(formatMoney(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: _busy ? null : _returnOrder,
                child: const Text('Захиалга буруу — буцаах'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _busy || !changed || allRemoved ? null : _save,
                child: const Text('Хадгалах'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Тооцоо авах ─────────────────────────────────────────────────────────────
Future<void> showSettlementSheet(BuildContext context, DeliveryController c, DeliveryOrder o) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
      child: _SettlementSheet(controller: c, order: o),
    ),
  );
}

class _SettlementSheet extends StatefulWidget {
  final DeliveryController controller;
  final DeliveryOrder order;
  const _SettlementSheet({required this.controller, required this.order});

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  final _cash = TextEditingController();
  final _transfer = TextEditingController();
  final _credit = TextEditingController();
  Promo? _promo;
  // null = ХАРААХАН МЭДЭГДЭЭГҮЙ — зээлийг ХААХГҮЙ, эцсийн шалгалтыг сервер хийнэ.
  num? _available;
  num? _outstanding;
  String? _preset = 'cash';
  bool _split = false;
  bool _busy = false;
  String? _error;

  num get total => widget.order.totalAmount;

  @override
  void initState() {
    super.initState();
    _applyPreset('cash');
    _load();
  }

  @override
  void dispose() {
    _cash.dispose();
    _transfer.dispose();
    _credit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final promo = await widget.controller.fetchPromo();
    if (!mounted) return;
    setState(() => _promo = promo);
    // Урамшуулал ирсний дараа анхдагч (бэлэн) дүнг хөнгөлөлттэй нь дахин тооцно.
    if (_preset != null) _applyPreset(_preset!);
    final storeId = widget.order.storeId;
    if (storeId == null) return;
    final balance = await widget.controller.fetchBalance(storeId);
    if (!mounted || balance == null) return;
    setState(() {
      _outstanding = balance.$1;
      _available = balance.$2;
    });
  }

  String _fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  void _applyPreset(String method) {
    final (cash, transfer, credit) = presetSplit(method, total, _promo);
    _cash.text = _fmt(cash);
    _transfer.text = _fmt(transfer);
    _credit.text = _fmt(credit);
    setState(() => _preset = method);
  }

  // Мөнгөн дүн — таслал нь МЯНГАТЫН тусгаарлагч («15,000» = 15000, 15 биш).
  num _read(TextEditingController c) => math.max(0, num.tryParse(c.text.trim().replaceAll(',', '')) ?? 0);

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final cash = _read(_cash), transfer = _read(_transfer), credit = _read(_credit);
    try {
      await widget.controller.settle(widget.order, cash: cash, transfer: transfer, credit: credit);
      final discount = promoDiscount(total, _promo, credit);
      final creditNote = credit > 0 ? ' — үүнээс ${formatMoney(credit)} зээл' : '';
      final promoNote = discount > 0 ? ' (урамшуулал −${formatMoney(discount)})' : '';
      widget.controller.setMessage(AppMessage.success('Тооцоо хийгдлээ$creditNote$promoNote.'));
      if (!mounted) return;
      final nav = Navigator.of(context);
      nav.pop();
      // Тооцоо амжилттай болмогц баримтыг автоматаар нээнэ — нэг товчоор хэвлэнэ.
      nav.push(MaterialPageRoute<void>(
        builder: (_) => OrderReceiptScreen(api: widget.controller.api, orderId: widget.order.id),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Тооцоо хийхэд алдаа гарлаа.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _splitField(String label, TextEditingController controller) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: label, suffixText: '₮'),
          onChanged: (_) => setState(() => _preset = null),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final credit = _read(_credit);
    final check = checkSplit(
      total: total,
      cash: _read(_cash),
      transfer: _read(_transfer),
      credit: credit,
      promo: _promo,
      available: _available,
    );
    final (statusText, statusColor) = switch (check.state) {
      SplitState.short => ('Дутуу: ${formatMoney(check.diff)} хуваарилаагүй байна.', AppColors.warning),
      SplitState.over => ('Илүү: ${formatMoney(-check.diff)}-аар хэтэрсэн байна.', AppColors.warning),
      SplitState.creditOver => ('Зээлийн хэсэг боломжит эрхээс (${formatMoney(_available)}) хэтэрсэн.', AppColors.warning),
      SplitState.ok => ('Дүн таарлаа', AppColors.success),
    };
    final promo = _promo;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Тооцоо авах', style: TextStyle(color: AppColors.muted)),
          Text(o.storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          if (o.isOnline) ...[
            const SizedBox(height: 8),
            const MessageBanner(AppMessage(
              'Онлайн захиалга — төлбөр аль хэдийн төлөгдсөн. Мөнгө авахгүй, зөвхөн барааг хүлээлгэн өгнө.',
            )),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: const Color(0xFFF1F7F4), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              const Text('Авах дүн', style: TextStyle(color: AppColors.muted)),
              Text(formatMoney(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.brand)),
            ]),
          ),
          if (promo != null) ...[
            const SizedBox(height: 8),
            Text(
              check.discount > 0
                  ? '${promo.name} −${formatAmount(promo.percent)}%: −${formatMoney(check.discount)} → төлөх дүн ${formatMoney(check.payable)}'
                  : '${promo.name} (−${formatAmount(promo.percent)}%): ${promo.description ?? 'зээлгүй (бэлэн/данс) төлбөрт хөнгөлнө.'}',
              style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
            ),
          ],
          if (_outstanding != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _Fact('Дэлгүүрийн авлага', formatMoney(_outstanding))),
              const SizedBox(width: 8),
              Expanded(child: _Fact('Боломжит зээл', _available == null ? '—' : formatMoney(_available))),
            ]),
          ],
          const SizedBox(height: 14),
          const Text('Төлбөрийн хэлбэр', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Бэлэн')),
              ButtonSegment(value: 'transfer', label: Text('Данс')),
              ButtonSegment(value: 'credit', label: Text('Зээл')),
            ],
            selected: {?_preset},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: (v) {
              if (v.isNotEmpty) _applyPreset(v.first);
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _split = !_split),
              icon: Icon(_split ? Icons.expand_less : Icons.expand_more),
              label: const Text('Хэсэгчлэн хуваах'),
            ),
          ),
          if (_split) ...[
            _splitField('Бэлэн', _cash),
            _splitField('Данс', _transfer),
            _splitField('Зээл', _credit),
          ],
          Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
          if (_available != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Зээлээр ${formatMoney(_available)} хүртэл тооцох боломжтой.', style: const TextStyle(color: AppColors.muted)),
            ),
          if (_error != null) ...[const SizedBox(height: 8), MessageBanner(AppMessage.error(_error!))],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy || check.state != SplitState.ok ? null : _confirm,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(_busy ? 'Тооцоо хийж байна…' : 'Тооцоо авах'),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
