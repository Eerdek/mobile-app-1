import 'package:flutter/material.dart';

import '../../core/date_range.dart';
import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/ui.dart';
import '../../printing/order_receipt.dart';
import 'seller_controller.dart';
import 'seller_logic.dart';
import 'seller_widgets.dart';
import 'store_sheets.dart';

/// Зээлтэй дэлгүүрүүд — ЗӨВХӨН өөрийн зээлээр хүргэсэн (/stores/my-credits).
/// ⚠ ТӨЛБӨР ТЭМДЭГЛЭХ товч ЭНД БАЙХГҮЙ — тооцоо авах нь зөвхөн админд.
class ReceivablesPage extends StatefulWidget {
  final SellerController controller;
  const ReceivablesPage({super.key, required this.controller});

  @override
  State<ReceivablesPage> createState() => _ReceivablesPageState();
}

class _ReceivablesPageState extends State<ReceivablesPage> {
  RecvView _view = RecvView.open;
  String _query = '';
  String _status = '';
  // ⚠ Анхдагч нь БҮГД — өнөөдрөөр бол хуучин өртэй дэлгүүрүүд нуугдана.
  DateRange _range = DateRange.preset(RangePreset.all);
  final Set<String> _open = {};
  // Дэлгүүр бүрийн задаргааны кэш. ⚠ Унасан хүсэлтийг кэшэнд үлдээхгүй.
  final Map<String, Future<Json>> _breakdown = {};

  SellerController get c => widget.controller;

  Future<Json> _fetch(String storeId) => _breakdown.putIfAbsent(storeId, () async {
    try {
      final res = await c.api.get('/stores/${Uri.encodeComponent(storeId)}/credits');
      return res is Json ? res : <String, dynamic>{};
    } catch (e) {
      _breakdown.remove(storeId);
      rethrow;
    }
  });

  /// ⚠ /orders/:id-г ХЭРЭГЛЭХГҮЙ — дэлгүүрийн зээлийн хүрээний тусдаа зам нь
  ///   хариуцагчид БҮХ баримтыг нээж өгнө.
  Future<void> _receipt(String storeId, String orderId) async {
    try {
      final d = await c.api.get('/stores/${Uri.encodeComponent(storeId)}/credits/${Uri.encodeComponent(orderId)}');
      if (!mounted || d is! Json) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderReceiptScreen(api: c.api, orderId: orderId, details: d),
        ),
      );
    } catch (e) {
      if (mounted) alertError(context, SellerController.errorText(e, 'Баримтын мэдээлэл татахад алдаа гарлаа.'));
    }
  }

  /// Админаар шалгуулах. ⚠ МӨНГӨ хөдөлгөхгүй; шалтгааныг ЗААВАЛ бичүүлнэ.
  Future<void> _check(String storeId, String orderId, num amount) async {
    final values = await showPromptDialog(
      context,
      title: 'Админаар шалгуулах',
      message:
          '№ ${shortId(orderId)} · үлдэгдэл ${formatMoney(amount)}. '
          'Админ энэ захиалгын төлбөрийг шалгаж, тооцоог бүртгэнэ. Та мөнгө бүртгэхгүй.',
      fields: const [
        PromptField('note', 'Шалтгаан (заавал)', required: true, hint: 'Жишээ: дэлгүүр 500,000₮ шилжүүлсэн гэж байна'),
      ],
      confirmLabel: 'Илгээх',
    );
    if (values == null) return;
    try {
      await c.api.post('/stores/${Uri.encodeComponent(storeId)}/credits/${Uri.encodeComponent(orderId)}/check', {
        'note': values['note'],
      });
    } catch (e) {
      if (mounted) alertError(context, SellerController.errorText(e, 'Хүсэлт илгээхэд алдаа гарлаа.'));
      return;
    }
    // Тухайн дэлгүүрийн задаргаа хуучирсан — зөвхөн үүнийг дахин татна.
    setState(() => _breakdown.remove(storeId));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final paid = _view == RecvView.paid;
        final list = filterReceivables(c.receivables, view: _view, query: _query, status: _status, range: _range);
        final sorted = paid ? ([...list]..sort((a, b) => recvPaidOf(b).compareTo(recvPaidOf(a)))) : list;
        final overdue = list.where((r) => r['status'] == 'overdue').toList();
        final overdueSum = overdue.fold<num>(0, (a, r) => a + toNum(r['outstanding']));
        final empty = c.receivables.isNotEmpty
            ? 'Шүүлтэд тохирох дэлгүүр алга.'
            : paid
            ? 'Төлбөр бүртгэгдсэн дэлгүүр алга.'
            : 'Одоогоор зээлтэй дэлгүүр алга.';
        return RefreshIndicator(
          onRefresh: () async {
            _breakdown.clear();
            await c.loadReceivables();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              // ⚠ Самбарын тоо нь ОДООГИЙН шүүлтийг дагана.
              Row(
                children: [
                  Expanded(
                    child: KpiTile(
                      label: paid ? 'Нийт төлсөн' : 'Нийт авлага',
                      value: formatMoney(
                        list.fold<num>(0, (a, r) => a + (paid ? recvPaidOf(r) : toNum(r['outstanding']))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KpiTile(label: 'Дэлгүүр', value: '${list.length}'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              KpiTile(
                label: 'Хэтэрсэн',
                value: overdue.isEmpty ? '0' : '${overdue.length} · ${formatMoney(overdueSum)}',
                accent: overdue.isEmpty ? null : AppColors.danger,
              ),
              const SizedBox(height: 12),
              SegmentedButton<RecvView>(
                segments: const [
                  ButtonSegment(value: RecvView.open, label: Text('Төлөгдөөгүй')),
                  ButtonSegment(value: RecvView.paid, label: Text('Төлсөн түүх')),
                ],
                selected: {_view},
                showSelectedIcon: false,
                // Харагдац солиход төлвийн сонголтыг ЦЭВЭРЛЭНЭ.
                onSelectionChanged: (v) => setState(() {
                  _view = v.first;
                  _status = '';
                }),
              ),
              const SizedBox(height: 8),
              SearchField(hint: 'Дэлгүүр, бүс хайх...', onChanged: (v) => setState(() => _query = v)),
              if (!paid) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Төлөв'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Бүх төлөв')),
                    DropdownMenuItem(value: 'overdue', child: Text('Хэтэрсэн')),
                    DropdownMenuItem(value: 'warning', child: Text('Ойртсон')),
                    DropdownMenuItem(value: 'normal', child: Text('Хэвийн')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? ''),
                ),
              ],
              const SizedBox(height: 8),
              // Хугацаа нь ТӨЛӨХ огноогоор.
              DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
              const SizedBox(height: 12),
              if (sorted.isEmpty) EmptyState(empty) else for (final r in sorted) _tile(r, paid),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(Json item, bool paid) {
    final storeId = '${item['storeId']}';
    final money = paid ? recvPaidOf(item) : toNum(item['outstanding']);
    final counts = item['dueCounts'] is Map ? item['dueCounts'] as Map : const {};
    final sub = [
      if (str(item['storeZone']) != null) 'Бүс: ${item['storeZone']}',
      if (item['status'] == 'overdue' && toInt(item['daysOverdue']) > 0) '${item['daysOverdue']} хоног хэтэрсэн',
      ...recvDueParts(item),
    ];
    return ExpandTile(
      key: ValueKey('recv:$storeId'),
      open: _open.contains(storeId),
      onToggle: (v) => setState(() => v ? _open.add(storeId) : _open.remove(storeId)),
      title: Text('${item['storeName'] ?? '-'}'),
      subtitle: Text(
        sub.isEmpty ? (str(item['storeOwner']) ?? '-') : sub.join(' · '),
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMoney(money), style: const TextStyle(fontWeight: FontWeight.w800)),
          recvStatusTag(item['status'], toInt(counts[item['status']])),
        ],
      ),
      children: [
        if (paid && toNum(item['outstanding']) > 0)
          Text('үлдэгдэл ${formatMoney(toNum(item['outstanding']))}', style: const TextStyle(color: AppColors.muted)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (str(item['storePhone']) != null)
              OutlinedButton.icon(
                onPressed: () => callPhone(str(item['storePhone'])),
                icon: const Icon(Icons.call_outlined, size: 16),
                label: const Text('Залгах'),
              ),
            OutlinedButton.icon(
              onPressed: () => openCustomerDetail(context, c, storeId),
              icon: const Icon(Icons.storefront_outlined, size: 16),
              label: const Text('Дэлгүүрийн дэлгэрэнгүй'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_open.contains(storeId))
          FutureBuilder<Json>(
            future: _fetch(storeId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  SellerController.errorText(snap.error!, 'Ачаалахад алдаа гарлаа.'),
                  style: const TextStyle(color: AppColors.muted),
                );
              }
              if (!snap.hasData) return const LoadingState('Ачааллаж байна…');
              return _breakdownView(snap.data!, storeId);
            },
          ),
      ],
    );
  }

  Widget _breakdownView(Json data, String storeId) {
    final orders = jsonList(data['orders']);
    if (orders.isEmpty) return const Text('Зээлээр авсан захиалга алга.', style: TextStyle(color: AppColors.muted));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          children: [
            Text('Нийт зээл ${formatMoney(toNum(data['totalCredit']))}'),
            Text('Төлсөн ${formatMoney(toNum(data['totalPaid']))}'),
            Text(
              'Үлдэгдэл ${formatMoney(toNum(data['outstanding']))}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final row in orders) _orderRow(row, storeId),
      ],
    );
  }

  Widget _orderRow(Json row, String storeId) {
    final remaining = toNum(row['remaining']);
    final covered = toNum(row['coveredAmount']);
    final check = row['checkRequest'] is Json ? row['checkRequest'] as Json : null;
    final Widget tag = remaining <= 0
        ? const Tag('Төлсөн', color: AppColors.success, background: AppColors.successSoft)
        : switch (row['dueStatus']) {
            'overdue' => const Tag('Хэтэрсэн', color: AppColors.danger, background: AppColors.dangerSoft),
            'warning' => const Tag.warning('Ойртсон'),
            _ => const Tag('Хэвийн', color: AppColors.success, background: AppColors.successSoft),
          };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('№${shortId(row['orderId'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              tag,
            ],
          ),
          Text(
            'Авсан ${formatDateTime(row['createdAt'])} · Төлөх ${formatDateTime(row['dueAt'])}'
            '${remaining > 0 && toInt(row['daysOverdue']) > 0 ? ' · ${row['daysOverdue']} хоног хэтэрсэн' : ''}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          Text(
            'Зээл ${formatMoney(toNum(row['amount']))} · Төлсөн ${covered > 0 ? formatMoney(covered) : '—'} · '
            'Үлдэгдэл ${remaining > 0 ? formatMoney(remaining) : '—'}${remaining > 0 && covered > 0 ? ' (хэсэгчлэн төлсөн)' : ''}',
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _receipt(storeId, '${row['orderId']}'),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('Баримт'),
              ),
              // Аль хэдийн хүсэлт гаргасан бол ТӨЛӨВ харагдана (давхар илгээхгүй).
              if (check != null)
                Tag.warning(
                  'Шалгуулж байна${str(check['requestedByName']) != null ? ' · ${check['requestedByName']}' : ''}',
                )
              else if (remaining > 0)
                OutlinedButton.icon(
                  onPressed: () => _check(storeId, '${row['orderId']}', remaining),
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: const Text('Шалгуулах'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
