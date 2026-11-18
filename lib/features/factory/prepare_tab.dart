import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/excel_export.dart';
import '../../core/format.dart';
import '../../core/ui.dart';
import 'factory_controller.dart';
import 'factory_logic.dart';
import 'factory_models.dart';
import 'factory_widgets.dart';
import 'sheet_screen.dart';

class PrepareTab extends StatefulWidget {
  final FactoryController controller;
  const PrepareTab({super.key, required this.controller});

  @override
  State<PrepareTab> createState() => _PrepareTabState();
}

class _PrepareTabState extends State<PrepareTab> {
  // Хураалтын төлөв ТӨХӨӨРӨМЖ БҮРД хадгалагдана — web-тэй ижил түлхүүр.
  static const _prepOpenKey = 'factoryPrepListOpen';
  static const _handOpenKey = 'factoryHandListOpen';
  bool _prepOpen = true;
  bool _handOpen = true;

  FactoryController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onMessage);
    _restoreOpen();
    c.loadPrepare();
  }

  @override
  void dispose() {
    c.removeListener(_onMessage);
    super.dispose();
  }

  // ⚠ Баннер урт жагсаалтын ДЭЭД талд — доош гүйлгэсэн үед бэлтгэл/хүлээлгэлтийн
  //   алдаа үл анзаарагдана. Шинэ алдаа бүрийг SnackBar-аар давхар гаргана.
  AppMessage? _shown;

  void _onMessage() {
    final m = c.message;
    if (m == null || identical(m, _shown) || m.kind != MessageKind.error || !mounted) return;
    _shown = m;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m.text), backgroundColor: AppColors.danger));
  }

  Future<void> _restoreOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _prepOpen = prefs.getBool(_prepOpenKey) ?? true;
        _handOpen = prefs.getBool(_handOpenKey) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _saveOpen(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _exportProducts() async {
    if (c.summary.products.isEmpty) {
      c.setMessage(const AppMessage.error('Татах бараа алга байна.'));
      return;
    }
    try {
      await shareExcel(
        fileBaseName: 'Бэлтгэх бараа ${ymd(DateTime.now())}',
        sheetName: 'Бэлтгэх бараа',
        rows: buildProductExcelRows(c.summary.products),
      );
    } catch (e) {
      c.setMessage(AppMessage.error('Excel үүсгэхэд алдаа гарлаа: $e'));
    }
  }

  Future<void> _exportHandover() async {
    if (c.orders.isEmpty) {
      c.setMessage(const AppMessage.error('Татах захиалга алга байна.'));
      return;
    }
    try {
      await shareExcel(
        fileBaseName: 'Хүлээлгэн өгөх ${ymd(DateTime.now())}',
        sheetName: 'Хүлээлгэн өгөх',
        rows: buildHandoverExcelRows(c.orders),
      );
    } catch (e) {
      c.setMessage(AppMessage.error('Excel үүсгэхэд алдаа гарлаа: $e'));
    }
  }

  void _openPrepSheet() {
    // ⚠ Хоосон хуудас хэвлэхээс сэргийлнэ — «хэвлэлээ, юу ч гарсангүй» нь
    //   принтер эвдэрсэн үү гэж эргэлзүүлдэг.
    if (sheetPending(c.orders).isEmpty) {
      c.setMessage(const AppMessage.error('Бэлтгэх захиалга алга байна.'));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SheetScreen(controller: c, mode: SheetMode.prep),
      ),
    );
  }

  void _openHandoverSheet([String? deliveryKey]) {
    final drivers = sheetDriverOptions(c.orders);
    if (drivers.isEmpty) {
      c.setMessage(const AppMessage.error('Хүлээгдэж буй захиалга алга — бүгдийг хүлээлгэж өгсөн байна.'));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SheetScreen(controller: c, mode: SheetMode.handover, deliveryKey: deliveryKey ?? drivers.first.key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => RefreshIndicator(
        onRefresh: c.loadPrepare,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            MessageBanner(c.message, onClose: () => c.setMessage(null)),
            _Kpis(totals: c.summary.totals),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Бэлтгэх барааны жагсаалт',
              subtitle: 'Ангиллаар бүлэглэсэн · бараа дээр дарж түгээгчийн задаргааг харна',
              actions: [
                IconButton(
                  tooltip: 'Бэлтгэх нэгтгэл хэвлэх',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: _openPrepSheet,
                ),
                IconButton(tooltip: 'Excel', icon: const Icon(Icons.download_outlined), onPressed: _exportProducts),
                IconButton(
                  tooltip: _prepOpen ? 'Жагсаалтыг хаах' : 'Жагсаалтыг нээх',
                  icon: Icon(_prepOpen ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() => _prepOpen = !_prepOpen);
                    _saveOpen(_prepOpenKey, _prepOpen);
                  },
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ⚠ Хураалтаас ГАДНА — жагсаалт хаалттай ч анхааруулга харагдана.
                  _LockNote(totals: c.summary.totals),
                  if (_prepOpen) _ProductBoard(controller: c),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Түгээгчид хүлээлгэн өгөх',
              subtitle:
                  'Түгээгч ирж бараагаа авахад «Өгөх» гэж тэмдэглэнэ. Батлагдаагүй захиалгыг батлагдсаны дараа өгнө.',
              actions: [
                IconButton(
                  tooltip: 'Түгээлтийн хуудас',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: _openHandoverSheet,
                ),
                IconButton(tooltip: 'Excel', icon: const Icon(Icons.download_outlined), onPressed: _exportHandover),
                IconButton(
                  tooltip: _handOpen ? 'Жагсаалтыг хаах' : 'Жагсаалтыг нээх',
                  icon: Icon(_handOpen ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() => _handOpen = !_handOpen);
                    _saveOpen(_handOpenKey, _handOpen);
                  },
                ),
              ],
              child: _handOpen ? _HandoverBoard(controller: c) : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  final SummaryTotals totals;
  const _Kpis({required this.totals});

  @override
  Widget build(BuildContext context) {
    // Эхний хоёр нь ГОЛ ШИЙДВЭР: юуг ЗААВАЛ хийх, юу нь бүрэлдээгүй байгаа.
    final tiles = [
      KpiTile(
        label: 'Заавал үйлдвэрлэх',
        value: formatQty(totals.lockedQty),
        caption: '${totals.lockedOrderCount} захиалга батлагдсан',
        accent: AppColors.brand,
      ),
      KpiTile(
        label: 'Батлагдаагүй',
        value: formatQty(totals.unlockedQty),
        caption: totals.unlockedOrderCount > 0
            ? '${totals.unlockedOrderCount} захиалга · өөрчлөгдөж болно'
            : 'бүх захиалга батлагдсан',
        accent: totals.unlockedQty > 0 ? AppColors.warning : null,
      ),
      KpiTile(
        label: 'Нийт бэлтгэх',
        value: formatQty(totals.totalQty),
        caption: '${totals.orderCount} захиалгаас нэгтгэв',
      ),
      KpiTile(label: 'Бараа төрөл', value: formatQty(totals.productKinds), caption: 'нэр төрлийн бараа'),
      KpiTile(label: 'Түгээгч', value: formatQty(totals.deliveryCount), caption: 'ирж авна'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 5 : 2;
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _LockNote extends StatelessWidget {
  final SummaryTotals totals;
  const _LockNote({required this.totals});

  @override
  Widget build(BuildContext context) {
    if (totals.unlockedOrderCount <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(10)),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(color: AppColors.text, height: 1.4),
          children: [
            TextSpan(
              text: '${formatQty(totals.unlockedOrderCount)} захиалгын ${formatQty(totals.unlockedQty)} ш',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ' бараа хараахан батлагдаагүй. Жагсаалтад «100'),
            TextSpan(
              text: '+${formatQty(totals.unlockedQty)}',
              style: const TextStyle(color: AppColors.warning, fontStyle: FontStyle.italic),
            ),
            const TextSpan(
              text:
                  ' ш» гэж бичсэн бол эхнийх нь батлагдсан, шар нь батлагдаагүй хэсэг. '
                  'Батлагдаагүйг борлуулагч засах, устгах боломжтой тул батлагдсан хэсгээ эхэлж бэлдээрэй.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductBoard extends StatelessWidget {
  final FactoryController controller;
  const _ProductBoard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.loadingSummary && c.summary.products.isEmpty) {
      return const LoadingState('Бэлтгэлийн нэгтгэлийг ачаалж байна…');
    }
    if (c.summary.products.isEmpty) {
      return EmptyState(
        c.summaryFailed
            ? 'Нэгтгэл ачаалж чадсангүй — доош татаж дахин оролдоно уу.'
            : 'Одоогоор бэлтгэх захиалга алга байна.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groupByCategory(c.summary.products)) ...[
          _CategoryHead(group: group),
          for (final p in group.items) _ProductTile(controller: c, product: p),
        ],
      ],
    );
  }
}

class _CategoryHead extends StatelessWidget {
  final CategoryGroup group;
  const _CategoryHead({required this.group});

  @override
  Widget build(BuildContext context) {
    final unconf = group.unlockedQty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.name.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.4,
                color: AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              textAlign: TextAlign.right,
              TextSpan(
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                children: [
                  TextSpan(text: '${group.items.length} төрөл · ${formatQty(group.totalQty - unconf)} ш'),
                  if (unconf > 0)
                    TextSpan(
                      text: ' +${formatQty(unconf)} батлагдаагүй',
                      style: const TextStyle(color: AppColors.warning, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final FactoryController controller;
  final SummaryProduct product;
  const _ProductTile({required this.controller, required this.product});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = product;
    final key = p.productId ?? p.name;
    final split = splitProduct(p);
    final lockedNeed = math.max(0, p.lockedQty);
    // Бүрэн бэлдсэн бараа: «86/86 бэлэн» чип л үлдэнэ (давхардлаас зайлсхийнэ).
    final prepFull = lockedNeed > 0 && p.preparedQty >= lockedNeed;
    final showQty = !prepFull || split.unlocked > 0;
    return ExpandTile(
      key: ValueKey('prod:$key'),
      open: c.openProducts.contains(key),
      onToggle: (open) => c.setOpen(c.openProducts, key, open),
      tint: split.unlocked > 0 ? const Color(0xFFFFFBF0) : null,
      title: Text(p.name),
      subtitle: Text(
        '${p.productCode != null ? 'Код ${p.productCode} · ' : ''}${p.orderCount} захиалга',
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressChip(p.preparedQty, lockedNeed),
          if (showQty) ...[const SizedBox(width: 6), QtyLabel(split.locked, split.unlocked, p.unitLabel)],
        ],
      ),
      children: [for (final part in p.byDelivery) _DeliveryPrepRow(controller: c, product: p, part: part)],
    );
  }
}

class _DeliveryPrepRow extends StatelessWidget {
  final FactoryController controller;
  final SummaryProduct product;
  final DeliveryPart part;
  const _DeliveryPrepRow({required this.controller, required this.product, required this.part});

  @override
  Widget build(BuildContext context) {
    final split = splitPart(part);
    final label = QtyLabel(
      split.locked,
      split.unlocked,
      product.unitLabel,
      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted),
    );
    // Заавал үйлдвэрлэх юу ч байхгүй (бүгд батлагдаагүй) бол тэмдэглэх зүйлгүй.
    if (split.locked <= 0) return AccRow(part.label, label, warn: split.unlocked > 0);
    final need = split.locked;
    final done = math.min(need, math.max(0, part.preparedQty));
    return _PrepLine(
      label: Text(part.label, style: TextStyle(color: split.unlocked > 0 ? AppColors.warning : null)),
      control: PrepControl(
        key: ValueKey('bulk:${product.productId ?? product.name}:${part.deliveryKey}'),
        done: done,
        need: need,
        ofLabel: Row(mainAxisSize: MainAxisSize.min, children: [const Text('/ '), label]),
        semanticName: '${product.name} — ${part.label}',
        onCommit: (qty) => controller.bulkPrep(product, part, qty: qty),
        onToggle: () => controller.bulkPrep(product, part, prepared: done < need),
      ),
    );
  }
}

// ── Түгээгчид хүлээлгэн өгөх ────────────────────────────────────────────────
class _HandoverBoard extends StatelessWidget {
  final FactoryController controller;
  const _HandoverBoard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.loadingOrders && c.orders.isEmpty) return const LoadingState('Захиалгуудыг ачаалж байна…');
    if (c.orders.isEmpty) {
      return EmptyState(
        c.ordersFailed ? 'Захиалга ачаалж чадсангүй — доош татаж дахин оролдоно уу.' : 'Бэлтгэх захиалга алга байна.',
      );
    }

    final groups = <String, List<ProductionOrder>>{};
    for (final o in c.orders) {
      groups.putIfAbsent(o.deliveryKey, () => []).add(o);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) _DriverGroup(controller: c, deliveryKey: entry.key, orders: entry.value),
      ],
    );
  }
}

class _DriverGroup extends StatelessWidget {
  final FactoryController controller;
  final String deliveryKey;
  final List<ProductionOrder> orders;
  const _DriverGroup({required this.controller, required this.deliveryKey, required this.orders});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final name = orders.first.deliveryLabel;
    // Явц нь ЗӨВХӨН батлагдсан захиалгаар — батлагдаагүйг хүлээлгэн өгөх боломжгүй.
    final confirmed = orders.where((o) => o.isLocked).toList();
    final unconfirmed = orders.length - confirmed.length;
    final total = confirmed.length;
    final handed = confirmed.where((o) => o.isHanded).length;
    final allHanded = total > 0 && handed == total;
    final sorted = [...orders]..sort(compareOrderForHandover);

    // Өдрийн задаргаа — нэгээс олон өдрийн захиалга хүлээгдэж байвал.
    final dayCounts = <String, (int, bool)>{};
    for (final o in sorted) {
      final day = orderDay(o.createdAt) ?? const OrderDay('Огноогүй', true);
      final prev = dayCounts[day.label];
      dayCounts[day.label] = ((prev?.$1 ?? 0) + 1, day.old);
    }

    final counts = [
      if (total > 0) '$total батлагдсан${allHanded ? ' · бүгд гарсан' : ' · $handed гарсан'}',
      if (unconfirmed > 0) '$unconfirmed батлагдаагүй',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: allHanded ? AppColors.success : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: allHanded ? AppColors.successSoft : const Color(0xFFF7F9FC),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: allHanded ? AppColors.success : AppColors.brand,
                      child: Text(
                        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (counts.isNotEmpty)
                            Text(counts, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (dayCounts.length > 1) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final e in dayCounts.entries)
                        e.value.$2 ? Tag.warning('${e.key} ${e.value.$1}') : Tag('${e.key} ${e.value.$1}'),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                if (total > 0)
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: handed / total,
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$handed/$total', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: c.busyHandover.contains('all:$deliveryKey')
                            ? null
                            : () async {
                                // ⚠ Нэг товчоор түгээгчийн БҮХ захиалга гарч, бэлэн барааны үлдэгдэл хасагдана.
                                final ok = await confirmDialog(
                                  context,
                                  title: allHanded ? 'Бүгдийг буцаах' : 'Бүгдийг өгөх',
                                  message: allHanded
                                      ? '«$name» түгээгчийн $total захиалгын хүлээлгэн өгөлтийг буцаах уу? Бараа үлдэгдэлд буцаж орно.'
                                      : '«$name» түгээгчид ${total - handed} захиалгыг хүлээлгэн өгөх үү? Бэлэн барааны үлдэгдлээс хасагдана.',
                                  confirmLabel: allHanded ? 'Буцаах' : 'Өгөх',
                                  danger: allHanded,
                                );
                                if (ok) c.toggleHandoverAll(deliveryKey);
                              },
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: Text(allHanded ? 'Бүгдийг буцаах' : 'Бүгдийг өгөх'),
                      ),
                    ],
                  )
                else
                  const Text('Батлахыг хүлээж байна', style: TextStyle(color: AppColors.warning)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            child: Column(
              children: [for (final o in sorted) _OrderTile(controller: c, order: o)],
            ),
          ),
        ],
      ),
    );
  }
}

// Мөрийн горим: edit — батлагдсан, гараагүй · done — гарсан (идэвхгүй, бүгд
// дүүрсэн харагдана) · plain — батлагдаагүй (тэмдэглэх боломжгүй).
enum _PrepMode { edit, done, plain }

class _OrderTile extends StatelessWidget {
  final FactoryController controller;
  final ProductionOrder order;
  const _OrderTile({required this.controller, required this.order});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final o = order;
    final mode = !o.isLocked
        ? _PrepMode.plain
        : o.isHanded
        ? _PrepMode.done
        : _PrepMode.edit;
    final items = [...o.items]..sort((a, b) => compareByCategory(a.categoryName, a.name, b.categoryName, b.name));
    final prepDone = items.where((i) => i.isPrepDone).length;
    final busy = c.busyHandover.contains(o.id);

    final Widget mark = o.isLocked
        ? FilledButton.tonalIcon(
            onPressed: busy
                ? null
                : () async {
                    // Өгөхийг нэг товчоор (ажлын урсгал хурдан); харин БУЦААХ нь
                    // ховор бөгөөд үлдэгдэл өөрчилдөг тул баталгаажуулна.
                    if (o.isHanded &&
                        !await confirmDialog(
                          context,
                          title: 'Хүлээлгэн өгөлт буцаах',
                          message: 'Энэ захиалгыг «өгөөгүй» болгох уу? Бараа үлдэгдэлд буцаж орно.',
                          confirmLabel: 'Буцаах',
                          danger: true,
                        )) {
                      return;
                    }
                    c.toggleHandover(o);
                  },
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: o.isHanded ? AppColors.success : null,
              foregroundColor: o.isHanded ? Colors.white : null,
            ),
            icon: Icon(o.isHanded ? Icons.check : Icons.outbox_outlined, size: 16),
            label: Text(o.isHanded ? 'Өгсөн' : 'Өгөх'),
          )
        : const Tag.warning('Батлагдаагүй');

    return ExpandTile(
      key: ValueKey('order:${o.id}'),
      open: c.openOrders.contains(o.id),
      onToggle: (open) => c.setOpen(c.openOrders, o.id, open),
      tint: o.isHanded
          ? const Color(0xFFF3FAF6)
          : !o.isLocked
          ? const Color(0xFFFFFBF0)
          : null,
      title: Text(o.storeName ?? '-'),
      subtitle: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          dayTag(o.createdAt),
          zoneTag(o.zone),
          Text(
            '${o.items.length} төрөл · ${formatQty(o.totalQty)} ш',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          if (mode == _PrepMode.edit && items.isNotEmpty) ProgressChip(prepDone, items.length),
        ],
      ),
      trailing: mark,
      children: items.isEmpty
          ? const [EmptyState('Барааны мэдээлэл алга.')]
          : [for (final item in items) _ItemRow(controller: c, order: o, item: item, mode: mode)],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final FactoryController controller;
  final ProductionOrder order;
  final ProductionItem item;
  final _PrepMode mode;
  const _ItemRow({required this.controller, required this.order, required this.item, required this.mode});

  @override
  Widget build(BuildContext context) {
    if (mode == _PrepMode.plain) {
      return AccRow(item.name, Text('${formatQty(item.qty)} ш', style: const TextStyle(fontWeight: FontWeight.w700)));
    }
    // ⚠ «done» нь ХАРАГДАЦ — гарсан захиалгын хадгалсан утга хөндөгдөхгүй.
    final locked = mode == _PrepMode.done;
    final done = locked ? item.qty : item.preparedQty;
    return _PrepLine(
      label: Text(item.name),
      control: PrepControl(
        key: ValueKey('item:${order.id}:${item.id}'),
        done: done,
        need: item.qty,
        disabled: locked,
        ofLabel: Text('/ ${formatQty(item.qty)} ш'),
        semanticName: item.name,
        onCommit: (qty) => controller.savePrep(order, item, qty),
        onToggle: () => controller.savePrep(order, item, item.isPrepDone ? 0 : item.qty),
      ),
    );
  }
}

// Нэр — бэлтгэлийн control. Нарийн дэлгэц дээр control нэрийн ДООР бууна
// (нэрийг тасдахгүй, тоо оруулах талбарыг шахахгүй).
class _PrepLine extends StatelessWidget {
  final Widget label;
  final Widget control;
  const _PrepLine({required this.label, required this.control});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 340
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: control),
              ],
            )
          : Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 8),
                control,
              ],
            ),
    ),
  );
}
