import 'package:flutter/material.dart';

import '../../core/date_range.dart';
import '../../core/format.dart';
import '../../core/ui.dart';
import '../../printing/order_receipt.dart';
import 'seller_controller.dart';
import 'seller_logic.dart';
import 'seller_widgets.dart';

/// Борлуулагчийн бүртгэсэн БҮХ захиалга. Түгжигдээгүйг засах/устгах, дурын
/// захиалгыг хуулж шинэ захиалга болгоно. Senior түгжээ тайлна/түгжинэ.
class MyOrdersPage extends StatefulWidget {
  final SellerController controller;
  final VoidCallback onOpenWorkspace;
  const MyOrdersPage({super.key, required this.controller, required this.onOpenWorkspace});

  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> {
  DateRange _range = DateRange.preset(RangePreset.today);
  String _query = '';
  MyOrderStatus _status = MyOrderStatus.all;
  final Set<String> _open = {};
  AppMessage? _message;

  SellerController get c => widget.controller;

  void _setMessage(AppMessage? m) {
    setState(() => _message = m);
    if (m != null && m.kind == MessageKind.error) alertError(context, m.text, title: 'Захиалга');
  }

  Future<void> _openInCart(Json order, {required bool edit}) async {
    try {
      final err = await c.openOrderInCart('${order['id']}', edit: edit);
      if (err != null) {
        _setMessage(AppMessage.error(err));
        return;
      }
      _setMessage(null);
      widget.onOpenWorkspace();
    } catch (e) {
      _setMessage(AppMessage.error(SellerController.errorText(e, 'Захиалга ачаалахад алдаа гарлаа.')));
    }
  }

  Future<void> _delete(Json order) async {
    final ok = await confirmDialog(
      context,
      title: 'Захиалга устгах',
      message:
          '${order['storeName'] ?? '-'} дэлгүүрийн №${shortId(order['id'])} захиалгыг устгах уу? Энэ үйлдлийг буцаах боломжгүй.',
      confirmLabel: 'Устгах',
      danger: true,
    );
    if (!ok) return;
    try {
      await c.deleteOrder('${order['id']}');
      _setMessage(const AppMessage.success('Захиалга устгагдлаа.'));
    } catch (e) {
      _setMessage(AppMessage.error(SellerController.errorText(e, 'Захиалга устгахад алдаа гарлаа.')));
    }
  }

  Future<void> _toggleLock(Json order, bool locked) async {
    final no = shortId(order['id']);
    final ok = await confirmDialog(
      context,
      title: locked ? 'Захиалга түгжих' : 'Түгжээ тайлах',
      message: locked
          ? '№$no захиалгыг буцааж түгжих үү? Түгжигдмэгц үйлдвэрийн бэлтгэх жагсаалтад орно.'
          : '№$no захиалгын түгжээг тайлах уу? Засварлах боломжтой болж, үйлдвэрийн жагсаалтаас түр гарна.',
      confirmLabel: locked ? 'Түгжих' : 'Тайлах',
    );
    if (!ok) return;
    try {
      await c.setOrderLock('${order['id']}', locked);
      _setMessage(
        AppMessage.success(
          locked ? 'Захиалга түгжигдлээ — үйлдвэрийн жагсаалтад орлоо.' : 'Түгжээ тайлагдлаа — одоо засварлаж болно.',
        ),
      );
    } catch (e) {
      _setMessage(AppMessage.error(SellerController.errorText(e, 'Түгжээ өөрчлөхөд алдаа гарлаа.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final rows = filterMyOrders(c.orders, query: _query, range: _range, status: _status);
        final empty = c.orders.isEmpty ? 'Одоогоор бүртгэсэн захиалга алга.' : 'Шүүлтэд тохирох захиалга алга.';
        return RefreshIndicator(
          onRefresh: () => c.refreshWith(c.loadOrders),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              MessageBanner(
                _message ?? c.message,
                onClose: () {
                  c.message = null;
                  setState(() => _message = null);
                },
              ),
              DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
              const SizedBox(height: 10),
              SearchField(hint: 'Дэлгүүр, дугаар, утас…', onChanged: (v) => setState(() => _query = v)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<MyOrderStatus>(
                  segments: const [
                    ButtonSegment(value: MyOrderStatus.all, label: Text('Бүгд')),
                    ButtonSegment(value: MyOrderStatus.delivered, label: Text('Хүргэсэн')),
                    ButtonSegment(value: MyOrderStatus.undelivered, label: Text('Хүргээгүй')),
                    ButtonSegment(value: MyOrderStatus.returned, label: Text('Буцаагдсан')),
                  ],
                  selected: {_status},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _status = v.first),
                ),
              ),
              const SizedBox(height: 12),
              if (!c.loaded && c.orders.isEmpty)
                const LoadingState('Ачаалж байна…')
              else if (rows.isEmpty)
                EmptyState(empty)
              else
                for (final o in rows) _orderTile(o),
            ],
          ),
        );
      },
    );
  }

  Widget _orderTile(Json o) {
    final id = '${o['id']}';
    final editable = canModifyOrder(o);
    final lockable = c.isSenior && (o['status'] == 'new' || o['status'] == 'assigned');
    return ExpandTile(
      key: ValueKey('my:$id'),
      open: _open.contains(id),
      onToggle: (v) => setState(() => v ? _open.add(id) : _open.remove(id)),
      title: Text('${o['storeName'] ?? '-'}'),
      subtitle: Text(
        '№${shortId(id)} · ${formatDateTime(o['createdAt'])}',
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatMoney(orderPayable(o)), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          lockTag(o),
        ],
      ),
      children: [
        AccRow('Төлөв', statusTag(o['status'])),
        for (final (label, key) in const [
          ('Данс', 'transferAmount'),
          ('Бэлэн', 'cashAmount'),
          ('Зээл', 'creditAmount'),
        ])
          if (toNum(o[key]) > 0)
            AccRow(label, Text(formatMoney(toNum(o[key])), style: const TextStyle(fontWeight: FontWeight.w700))),
        if (toNum(o['discountAmount']) > 0) ...[
          AccRow('Барааны дүн', Text(formatMoney(toNum(o['totalAmount'])))),
          AccRow('Урамшуулал', Text('−${formatMoney(toNum(o['discountAmount']))}')),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(onPressed: () => OrderReceiptScreen.open(context, c.api, id), child: const Text('Баримт')),
            OutlinedButton(onPressed: () => _openInCart(o, edit: false), child: const Text('Хуулах')),
            if (editable) FilledButton(onPressed: () => _openInCart(o, edit: true), child: const Text('Засах')),
            if (editable)
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _delete(o),
                child: const Text('Устгах'),
              ),
            if (lockable)
              OutlinedButton.icon(
                onPressed: () => _toggleLock(o, o['locked'] != true),
                icon: Icon(o['locked'] == true ? Icons.lock_open : Icons.lock_outline, size: 16),
                label: Text(o['locked'] == true ? 'Тайлах' : 'Түгжих'),
              ),
          ],
        ),
      ],
    );
  }
}
