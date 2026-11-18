// Захиалгын баримт — web-ийн receipt.js-ийн хуулбар (борлуулагч ба түгээгч
// ижил форматтай). Өгөгдөл нь GET /orders/:id-ийн хариу (Map) — талбарын нэр
// web-тэй ижил тул задлалгүй шууд уншина.
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/ui.dart';
import '../core/units.dart';
import 'print_button.dart';
import 'receipt.dart';

class ReceiptConfig {
  static const companyName = 'АКИ фүүдс ххк';
  static const companyRegister = '8455686';
  // Богино нэр — банк, данс, IBAN гурвыг НЭГ мөрөнд багтаана (72мм = 46 тэмдэгт).
  static const bankShort = 'ХХБ';
  static const bankAccount = '820026952';
  static const bankIban = '780004000';
  static const vatRate = 1 / 11;
  static const notes = [
    'Худалдан авсан барааны төлбөрөө хувь хүний дансруу шилжүүлэхгүй байхыг анхаарна уу.',
    'Хувь хүний дансруу хийсэн төлбөрийг гүйцэтгээгүйд тооцно.',
    'Харилцагч та бараа хүлээн авахдаа бүтээгдэхүүн нэг бүрийн огноо, биет байдлыг шалгаж хүлээн авна уу.',
    'Төлбөрийн хугацаа: Худалдан авагч талтай тохиролцсоны дагуу.',
  ];
}

const _paymentLabels = {'cash': 'Бэлэн', 'credit': 'Зээл', 'transfer': 'Дансаар'};

/// Төлбөрийн задаргаа [шошго, дүн]. Задаргаагүй хуучин мөрт paymentMethod-ыг бүтэн дүнгээр.
List<(String, num)> receiptPaymentParts(Map<String, dynamic> d) {
  final parts = <(String, num)>[];
  if (toNum(d['cashAmount']) > 0) parts.add(('Бэлэн', toNum(d['cashAmount'])));
  if (toNum(d['transferAmount']) > 0) parts.add(('Дансаар', toNum(d['transferAmount'])));
  if (toNum(d['creditAmount']) > 0) parts.add(('Зээл', toNum(d['creditAmount'])));
  final method = d['paymentMethod'];
  if (parts.isEmpty && method != null) {
    parts.add((_paymentLabels[method] ?? 'Тодорхойлоогүй', toNum(d['totalAmount'])));
  }
  return parts;
}

String _orderKind(Map<String, dynamic> d) {
  if (d['source'] == 'online') return 'Онлайн';
  return d['storeType'] == 'wholesale' ? 'Бөөний' : 'Маркет';
}

String _s(Object? v, [String fallback = '-']) {
  final s = v == null ? '' : '$v';
  return s.trim().isEmpty ? fallback : s;
}

List<Map<String, dynamic>> _items(Object? v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const <Map<String, dynamic>>[];

class OrderReceiptDoc extends StatelessWidget {
  final Map<String, dynamic> details;
  const OrderReceiptDoc({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final d = details;
    final subtotal = toNum(d['subtotal'] ?? d['totalAmount']);
    final returnAmount = toNum(d['returnAmount']);
    final discount = toNum(d['discountAmount']);
    final shrinkage = toNum(d['shrinkageAmount']);
    final payable = toNum(d['totalAmount']) - discount;
    // Ангиллаар — дэлгүүр бараагаа төрлөөр нь шалгадаг.
    final items = sortItemsByCategory(_items(d['items']));
    final totalQty = items.fold<num>(0, (s, i) => s + toNum(i['qty']));
    final vat = subtotal * ReceiptConfig.vatRate;
    final isOnline = d['source'] == 'online';
    final memoCode = d['storeCode'] != null ? '${d['storeCode']}' : '—';
    final memoText = isOnline ? _s(d['externalOrderNo'], '—') : memoCode;
    final payParts = receiptPaymentParts(d);
    final paymentLabel = payParts.isEmpty ? 'Тодорхойлоогүй' : payParts.map((p) => p.$1).join(', ');
    final seller = '${_s(d['sellerName'], 'Борлуулагч')}${d['sellerPhone'] != null ? ' ${d['sellerPhone']}' : ''}';
    final delivery = d['deliveryName'] != null
        ? '${d['deliveryName']}${d['deliveryPhone'] != null ? ' ${d['deliveryPhone']}' : ''}'
        : '—';
    final returnItems = _items(d['returnItems']);
    final returns = _items(d['returns']);

    return ReceiptFrame(children: [
      const RTitle('ЗАХИАЛГЫН БАРИМТ'),
      RLine.text('Захиалга авсан огноо:', receiptDate(d['createdAt'])),
      RLine.text('Бараа хүлээлгэж өгсөн:', d['deliveredAt'] != null ? receiptDate(d['deliveredAt']) : '—'),
      RLine.text('Баримтын дугаар:', '№ ${orderNo(d['id'])}'),
      RLine.text('Захиалгын төрөл:', _orderKind(d)),
      RLine.text('Төлбөрийн хэлбэр:', paymentLabel),
      const _RSection('Харилцагчийн мэдээлэл'),
      if (isOnline) ...[
        RLine.text('Харилцагч:', _s(d['customerName'])),
        RLine.text('Харилцагч утас:', _s(d['customerPhone'] ?? d['storePhone'])),
        if (d['customerEmail'] != null) RLine.text('И-мэйл:', _s(d['customerEmail'])),
        RLine.text('Хүргэх хаяг:', _s(d['customerAddress'] ?? d['storeAddress'])),
        RLine.text('Сайтын дугаар:', _s(d['externalOrderNo'])),
      ] else ...[
        RLine.text('Харилцагч код:', memoCode),
        RLine.text('Харилцагч:', _s(d['storeName'])),
        RLine.text('Харилцагч РД:', _s(d['storeRegister'])),
        RLine.text('Харилцагч утас:', _s(d['storePhone'])),
        RLine.text('Хаяг:', _s(d['storeAddress'])),
      ],
      const _RSection('Бараа нийлүүлэгчийн мэдээлэл'),
      RLine.text('Нийлүүлэгч:', '${ReceiptConfig.companyName} · РД ${ReceiptConfig.companyRegister}'),
      if (!isOnline) RLine.text('Төлөөлөгч:', seller),
      RLine.text('Түгээгч:', delivery),
      RLine.text('Данс:', '${ReceiptConfig.bankShort} ${ReceiptConfig.bankAccount} · IBAN ${ReceiptConfig.bankIban}'),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(TextSpan(children: [
          const TextSpan(text: 'Гүйлгээний утга дээр '),
          TextSpan(text: memoText, style: receiptBold),
          TextSpan(text: isOnline ? ' дугаарыг бичнэ үү.' : ' кодыг бичнэ үү.'),
        ])),
      ),
      const RSep(),
      _ItemsTable(items),
      const RSep(),
      if (returnAmount > 0) ...[
        const _RSection('БУЦААЛТЫН БАРИМТ'),
        if (returnItems.isNotEmpty)
          _ItemsTable(returnItems)
        else
          for (final r in returns) Text('${r['returned_item_summary'] ?? r['reason'] ?? 'Буцаалт'}'),
        RLine.text('Нийт буцаалтын дүн:', formatMoney(returnAmount)),
        const RSep(),
      ],
      const SizedBox(height: 7),
      RLine.text('Нийт барааны тоо:', formatAmount(totalQty)),
      RLine.text('Нийлүүлсэн барааны дүн:', formatMoney(subtotal)),
      if (shrinkage > 0) RLine.text('Хорогдол:', '−${formatMoney(shrinkage)}'),
      if (discount > 0) RLine.text('Урамшуулал:', '−${formatMoney(discount)}'),
      RLine.text('НӨАТ дүн:', moneyDecimal(vat)),
      if (returnAmount > 0) RLine.text('Буцаалт:', '−${formatMoney(returnAmount)}'),
      RLine.text('Төлөх дүн:', formatMoney(payable), strong: true),
      if (payParts.length > 1)
        for (final p in payParts) RLine.text('— ${p.$1}:', formatMoney(p.$2)),
      if (d['note'] != null && '${d['note']}'.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Тайлбар: ', style: receiptBold),
            TextSpan(text: '${d['note']}'),
          ])),
        ),
      const _RSection('Санамж'),
      for (final (i, note) in ReceiptConfig.notes.indexed)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 24, child: Text('${i + 1}.', style: const TextStyle(fontSize: 16))),
            Expanded(child: Text(note, style: const TextStyle(fontSize: 16))),
          ]),
        ),
      const SizedBox(height: 18),
      const Text('Хүлээн авсан: ____________________'),
    ]);
  }
}

String orderNo(Object? id) {
  final s = '${id ?? ''}';
  return (s.length > 8 ? s.substring(0, 8) : s).toUpperCase();
}

class _RSection extends StatelessWidget {
  final String text;
  const _RSection(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(text.toUpperCase(), textAlign: TextAlign.center, style: receiptBold),
      );
}

/// Барааны хүснэгт — тоон баганууд ТОГТМОЛ өргөнтэй (web: 42 / 86 / 118px),
/// нэрийн багана үлдсэнийг эзэлнэ. Бааркод нэртэй нэг нүдэнд.
class _ItemsTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _ItemsTable(this.items);

  static const _cell = TextStyle(fontSize: 18);
  static const _head = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    TableRow row(List<Widget> cells, {bool head = false}) => TableRow(
          decoration: head ? const BoxDecoration(border: Border(bottom: BorderSide(width: 2))) : null,
          children: [for (final c in cells) Padding(padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2), child: c)],
        );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: FixedColumnWidth(42),
        2: FixedColumnWidth(86),
        3: FixedColumnWidth(118),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        row(const [
          Text('Барааны нэр / Бааркод', style: _head),
          Text('Тоо', style: _head, textAlign: TextAlign.right),
          Text('Үнэ', style: _head, textAlign: TextAlign.right),
          Text('Дүн', style: _head, textAlign: TextAlign.right),
        ], head: true),
        for (final item in items)
          () {
            final barcode = item['barcode'] ?? item['productCode'];
            // ⚠ БАГЦЫН мөрөнд unitPrice нь БАГЦЫН үнэ, qty нь ФИЗИК ШИРХЭГ —
            //   захиалсан НЭГЖИЙГ бичээд ширхэгийг нэрийн доор тайлбарлана.
            final pack = isPack(item);
            final qty = pack ? orderedQtyOf(item) : toNum(item['qty']);
            return row([
              Text.rich(
                TextSpan(style: _cell, children: [
                  TextSpan(text: '${item['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (barcode != null) TextSpan(text: ' $barcode'),
                  if (pack) TextSpan(text: ' ${formatUnitsShort(item)}'),
                ]),
              ),
              Text(formatAmount(qty), style: _cell, textAlign: TextAlign.right),
              Text(formatMoney(toNum(item['unitPrice'])), style: _cell, textAlign: TextAlign.right),
              Text(formatMoney(toNum(item['lineTotal'])), style: _cell, textAlign: TextAlign.right),
            ]);
          }(),
      ],
    );
  }
}

/// Баримт харах + хэвлэх дэлгэц. [details] өгөгдвөл шууд, эс бөгөөс
/// GET /orders/:id-аас татна.
class OrderReceiptScreen extends StatefulWidget {
  final ApiClient api;
  final String orderId;
  final Map<String, dynamic>? details;
  const OrderReceiptScreen({super.key, required this.api, required this.orderId, this.details});

  static Future<void> open(BuildContext context, ApiClient api, String orderId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderReceiptScreen(api: api, orderId: orderId)));

  @override
  State<OrderReceiptScreen> createState() => _OrderReceiptScreenState();
}

class _OrderReceiptScreenState extends State<OrderReceiptScreen> {
  final GlobalKey _key = GlobalKey();
  Map<String, dynamic>? _details;
  String? _error;

  @override
  void initState() {
    super.initState();
    _details = widget.details;
    if (_details == null) _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.get('/orders/${Uri.encodeComponent(widget.orderId)}');
      if (!mounted) return;
      setState(() => _details = res is Map<String, dynamic> ? res : <String, dynamic>{});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : 'Баримтын мэдээлэл татахад алдаа гарлаа.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    return Scaffold(
      appBar: AppBar(title: const Text('Захиалгын баримт')),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: PrintButton(boundaryKey: _key),
              ),
            ),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: MessageBanner(AppMessage.error(_error!)))
          : d == null
              ? const LoadingState('Баримт ачаалж байна…')
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
                      ),
                      child: FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(key: _key, child: OrderReceiptDoc(details: d)),
                      ),
                    ),
                  ],
                ),
    );
  }
}
