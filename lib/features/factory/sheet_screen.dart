import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/ui.dart';
import '../../printing/print_button.dart';
import '../../printing/receipt.dart';
import 'factory_controller.dart';
import 'factory_logic.dart';
import 'factory_models.dart';

// Түгээлтийн хуудас (түгээгч тус бүрийн ачаа, дэлгүүрээр) ба бэлтгэх нэгтгэл
// (бүх түгээгч, бараагаар). Захиалгын баримт БИШ — үнэ, төлбөр байхгүй.
//
// ⚠ Утсан дээр A4 горим БАЙХГҮЙ — web дээр ч утсан дээр үргэлж 72мм.
enum SheetMode { handover, prep }

class SheetScreen extends StatefulWidget {
  final FactoryController controller;
  final SheetMode mode;
  final String? deliveryKey;

  const SheetScreen({super.key, required this.controller, required this.mode, this.deliveryKey});

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  String? _deliveryKey;
  // ⚠ ХООСОН = «бүгд».
  List<String> _days = const [];
  List<String> _zones = const [];

  FactoryController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _deliveryKey = widget.deliveryKey;
  }

  List<ProductionOrder> get _scopeOrders =>
      widget.mode == SheetMode.prep ? c.orders : c.orders.where((o) => o.deliveryKey == _deliveryKey).toList();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final orders = _scopeOrders;
        // ⚠ Өдөр солиход сонгосон бүс байхгүй болж болно — хоосон хуудаснаас сэргийлнэ.
        final zoneOptions = sheetZoneOptions(orders, _days);
        final validZones = zoneOptions.map((z) => z.key).toSet();
        final zones = _zones.where(validZones.contains).toList();
        final dayOptions = sheetDayOptions(orders);

        final rows = sheetVisibleStops(orders, _days, zones);
        final totals = sheetTotals(rows);
        final zoneLabel = selectionLabel(zoneOptions, zones, 'Бүх бүс');
        final dayLabel = selectionLabel(dayOptions, _days, 'Бүгд');
        final orderCount = rows.fold<int>(0, (s, r) => s + r.stop.orderCount);
        final lines = widget.mode == SheetMode.prep
            ? prepLineCount(totals)
            : handoverLineCount(rows, totals.items.length);
        final empty = rows.isEmpty;

        final title = widget.mode == SheetMode.prep ? 'Бэлтгэх нэгтгэл' : 'Түгээлтийн хуудас';
        final who = widget.mode == SheetMode.prep
            ? null
            : (orders.isNotEmpty ? orders.first.deliveryLabel : 'Түгээгч оноогоогүй');

        final summary = widget.mode == SheetMode.prep
            ? '$zoneLabel · ${rows.length} дэлгүүр · $orderCount захиалга · ${totals.items.length} нэр төрөл · '
                  '${formatQty(totals.doneQty)}/${formatQty(totals.totalQty)}ш бэлдсэн · 72мм роль · ≈${sheetLengthCm(lines)} см'
            : '$dayLabel · $zoneLabel · ${rows.length} дэлгүүр · $orderCount захиалга · ${totals.items.length} нэр төрөл · '
                  '${formatQty(totals.totalQty)}ш · 72мм роль · ≈${sheetLengthCm(lines)} см';

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (who != null) Text(who, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: PrintButton(boundaryKey: _boundaryKey, enabled: !empty),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              if (widget.mode == SheetMode.handover) ...[
                // ⚠ Түгээгч нь ГАНЦ сонголттой — хоёр түгээгчийг нийлүүлбэл машин андуурч ачина.
                _FilterRow(
                  label: 'Түгээгч',
                  options: sheetDriverOptions(c.orders),
                  isSelected: (key) => key == _deliveryKey,
                  onTap: (key) => setState(() => _deliveryKey = key),
                ),
              ],
              _FilterRow(
                label: 'Огноо',
                options: dayOptions,
                isSelected: (key) => key == 'all' ? _days.isEmpty : _days.contains(key),
                onTap: (key) => setState(() => _days = toggleSelection(_days, key)),
              ),
              // ⚠ Бүсийн шүүлтүүр — үйлдвэр ачаагаа бүсээр нь бэлдэж хэвлэдэг тул ГОЛ хэрэгсэл.
              _FilterRow(
                label: 'Бүс',
                options: zoneOptions,
                isSelected: (key) => key == 'all' ? zones.isEmpty : zones.contains(key),
                onTap: (key) => setState(() => _zones = toggleSelection(zones, key)),
              ),
              const SizedBox(height: 4),
              Text(summary, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              if (lines > sheetMaxLines) ...[
                const SizedBox(height: 8),
                MessageBanner(
                  AppMessage.warning(
                    widget.mode == SheetMode.prep
                        ? 'Нэгтгэл хэт урт тул Bluetooth-оор хэвлэхэд доод хэсэг эвдэрч болзошгүй. Бүсээр нь хувааж хэвлэнэ үү.'
                        : '${rows.length} дэлгүүрийн хуудас хэт урт (~1.2 метр). Бүсээр нь тусад нь хэвлэнэ үү.',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (empty)
                const EmptyState('Сонгосон шүүлтүүрт хүлээгдэж буй захиалга алга.')
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
                  ),
                  // 576 цэгийн хуудсыг дэлгэцийн өргөнд багтааж харуулна.
                  // RepaintBoundary нь FittedBox-ийн ДОТОР — зураг үргэлж 576 өргөнтэй.
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: widget.mode == SheetMode.prep
                          ? _PrepSheetDoc(
                              orders: orders,
                              days: _days,
                              rows: rows,
                              totals: totals,
                              zoneLabel: zoneLabel,
                              orderCount: orderCount,
                            )
                          : _HandoverSheetDoc(
                              driverName: who ?? '',
                              dayLabel: dayLabel,
                              zoneLabel: zoneLabel,
                              rows: rows,
                              totals: totals,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final List<FilterOption> options;
  final bool Function(String key) isSelected;
  final ValueChanged<String> onTap;

  const _FilterRow({required this.label, required this.options, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final o in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text('${o.label}  ${o.count}'),
                      selected: isSelected(o.key),
                      showCheckmark: false,
                      onSelected: (_) => onTap(o.key),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Цаасан дээрх агуулга ────────────────────────────────────────────────────
// Цаасан дээрх тоо: бүрэн бэлдсэн → «5ш ■», хэсэгчлэн → «4/5ш □», үгүй → «5ш □».
// ⚠ Дутуу бол ХОЁУЛАНГ нь бичнэ — зөвхөн үлдсэнийг бичвэл захиалсан тоо алга болно.
InlineSpan _qtyCell(int qty, int? prepared) {
  final done = (prepared ?? 0).clamp(0, 1 << 30);
  final String text;
  final bool on;
  if (done >= qty && qty > 0) {
    (text, on) = ('${formatQty(qty)}ш', true);
  } else if (done > 0) {
    (text, on) = ('${formatQty(done)}/${formatQty(qty)}ш', false);
  } else {
    (text, on) = ('${formatQty(qty)}ш', false);
  }
  return TextSpan(children: [TextSpan(text: text), tickBox(on: on)]);
}

class _PrepSheetDoc extends StatelessWidget {
  final List<ProductionOrder> orders;
  final List<String> days;
  final List<NumberedStop> rows;
  final SheetTotals totals;
  final String zoneLabel;
  final int orderCount;

  const _PrepSheetDoc({
    required this.orders,
    required this.days,
    required this.rows,
    required this.totals,
    required this.zoneLabel,
    required this.orderCount,
  });

  @override
  Widget build(BuildContext context) {
    // ⚠ Ангиллын толгойг ЗӨВХӨН ангилал СОЛИГДОХОД — мөр бүрд бичвэл цаас 2 дахин уртсана.
    final children = <Widget>[];
    String? currentCat;
    for (final entry in totals.items) {
      final cat = (totals.cats[entry.key] ?? '').trim();
      if (currentCat != cat) {
        currentCat = cat;
        children.add(RHead(cat.isEmpty ? noCategory : cat));
      }
      children.add(RLine(TextSpan(text: entry.key), _qtyCell(entry.value, totals.prep[entry.key])));
    }
    final total = totals.totalQty;
    final done = totals.doneQty;
    final daySummary = sheetDaySummary(orders, days);
    return ReceiptFrame(
      children: [
        const RTitle('БЭЛТГЭХ НЭГТГЭЛ'),
        // Огноо ТОЛГОЙД — өдрөөр БЛОКЛОХГҮЙ (нэг барааг хоёр удаа савлахгүйн тулд).
        RNote(daySummary.isEmpty ? 'Огноогүй' : daySummary),
        RNote('$zoneLabel · ${rows.length} дэлгүүр · $orderCount захиалга · ${totals.items.length} нэр төрөл'),
        const RSep(),
        if (children.isEmpty) RLine.text('Бэлтгэх бараа алга', '') else ...children,
        const RSep(),
        RLine.text('Нийт ширхэг:', '${formatQty(total)}ш', strong: true),
        RLine.text('Бэлдсэн:', '${formatQty(done)}ш', strong: true),
        RLine.text('Үлдсэн:', '${formatQty(total - done < 0 ? 0 : total - done)}ш', strong: true),
        RLine.text('Хэвлэсэн:', stamp()),
      ],
    );
  }
}

class _HandoverSheetDoc extends StatelessWidget {
  final String driverName;
  final String dayLabel;
  final String zoneLabel;
  final List<NumberedStop> rows;
  final SheetTotals totals;

  const _HandoverSheetDoc({
    required this.driverName,
    required this.dayLabel,
    required this.zoneLabel,
    required this.rows,
    required this.totals,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    // Бүс солигдох бүрд толгой. Дугаарлалт нь БҮХ хуудсаар тасралтгүй.
    var first = true;
    String? lastZone;
    for (final row in rows) {
      final stop = row.stop;
      if (first || stop.zone != lastZone) {
        first = false;
        lastZone = stop.zone;
        final count = rows.where((r) => r.stop.zone == stop.zone).length;
        blocks.add(RHead('${stop.zone ?? zoneNoneLabel} · $count дэлгүүр'));
      }
      blocks.add(const RSep());
      // ⚠ БҮСИЙГ дэлгүүрийн мөрөнд Ч бичнэ — дунд нь «энэ аль бүсийнх вэ» гэж дээш хайхгүй.
      blocks.add(
        RLine(
          TextSpan(
            children: [
              TextSpan(text: '${row.no}. ${stop.name}'),
              if (stop.orderCount > 1)
                TextSpan(
                  text: ' (${stop.orderCount} захиалга)',
                  style: const TextStyle(fontWeight: FontWeight.w400),
                ),
              TextSpan(
                text: ' ${stop.zone ?? 'Бүсгүй'}',
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
            ],
          ),
          TextSpan(text: stop.code != null ? '№${stop.code}' : '—'),
          strong: true,
        ),
      );
      final items = stop.sortedItems;
      if (items.isEmpty) {
        blocks.add(RLine.text('Барааны мэдээлэл алга', ''));
      } else {
        for (final item in items) {
          blocks.add(RLine(TextSpan(text: item.key), _qtyCell(item.value, stop.prep[item.key])));
        }
      }
      blocks.add(RLine.text('Огноо:', stop.days.join(', ')));
    }

    final orderCount = rows.fold<int>(0, (s, r) => s + r.stop.orderCount);
    return ReceiptFrame(
      children: [
        const RTitle('ТҮГЭЭЛТИЙН ХУУДАС'),
        RLine.text('Түгээгч:', driverName),
        RLine.text('Хэвлэсэн:', stamp()),
        RLine.text('Өдөр:', dayLabel),
        // ⚠ Аль бүсийг хэвлэж байгааг ЦААСАН ДЭЭР — хэдэн хуудас холилдохгүй.
        RLine.text('Бүс:', zoneLabel),
        RLine.text('Дэлгүүр:', '${rows.length}'),
        ...blocks,
        const RSep(),
        // ⚠ ХАМГИЙН СҮҮЛД нийт барааны нэгтгэл — «нийтдээ хэдийг барих вэ».
        RHead('Нийт бараа · ${totals.items.length} нэр төрөл'),
        if (totals.items.isEmpty)
          RLine.text('Бараа алга', '')
        else
          for (final item in totals.items) RLine(TextSpan(text: item.key), _qtyCell(item.value, totals.prep[item.key])),
        const RSep(),
        RLine.text('Нийт ширхэг:', '${formatQty(totals.totalQty)}ш', strong: true),
        RLine.text('Нийт дэлгүүр:', '${rows.length}', strong: true),
        RLine.text('Нийт захиалга:', '$orderCount', strong: true),
      ],
    );
  }
}
