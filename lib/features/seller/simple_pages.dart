import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/date_range.dart';
import '../../core/format.dart';
import '../../core/ui.dart';
import 'seller_controller.dart';
import 'seller_logic.dart';
import 'store_workspace.dart' show ReturnItemCard;

const _monthNames = ['1-р', '2-р', '3-р', '4-р', '5-р', '6-р', '7-р', '8-р', '9-р', '10-р', '11-р', '12-р'];

// ── Самбар ──────────────────────────────────────────────────────────────────
class DashboardPage extends StatefulWidget {
  final SellerController controller;
  final VoidCallback onNewOrder;
  final VoidCallback onReceivables;
  const DashboardPage({super.key, required this.controller, required this.onNewOrder, required this.onReceivables});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DateRange _range = DateRange.preset(RangePreset.today);

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = dashStats(c.orders, _range);
        final isAll = _range.from == null && _range.to == null;
        // ⚠ Гарчиг нь ямар хугацааны тоо болохыг ӨӨРӨӨ хэлэх ёстой.
        final heroLabel = _range.isToday
            ? 'Өнөөдрийн борлуулалт'
            : isAll
            ? 'Нийт борлуулалт'
            : 'Борлуулалт';
        final heroSub = _range.isToday ? '${s.orderCount} захиалга' : '${s.orderCount} захиалга · ${_range.label}';
        // ⚠ АВЛАГА нь БҮХ ХУГАЦААНЫ дүн — хугацааны шүүлтээс хамаарахгүй.
        final recv = c.receivables;
        final collected = recv.fold<num>(0, (a, r) => a + recvPaidOf(r));
        final open = recv.where((r) => toNum(r['outstanding']) > 0).toList();
        final overdue = open.where((r) => r['status'] == 'overdue').toList();
        final months = monthlySales(c.orders);
        final maxMonth = months.fold<num>(1, (m, e) => math.max(m, e.$2));
        return RefreshIndicator(
          onRefresh: c.loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              DateRangeBar(
                value: _range,
                presets: const [RangePreset.today, RangePreset.week, RangePreset.month, RangePreset.all],
                onChanged: (r) => setState(() => _range = r),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(heroLabel, style: const TextStyle(color: Colors.white70)),
                          Text(
                            formatMoney(s.sales),
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                          ),
                          Text(heroSub, style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brand),
                      tooltip: 'Шинэ захиалга бүртгэх',
                      onPressed: widget.onNewOrder,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: KpiTile(
                      label: 'Хүргэгдсэн',
                      value: formatMoney(s.deliveredAmount),
                      caption: '${s.deliveredCount} захиалга',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KpiTile(
                      label: 'Хүлээгдэж буй',
                      value: formatMoney(s.pendingAmount),
                      caption: '${s.pendingCount} захиалга',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: KpiTile(
                      label: 'Данс + Бэлэн',
                      value: formatMoney(s.paid),
                      caption: 'Данс ${formatMoney(s.transfer)} · Бэлэн ${formatMoney(s.cash)}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KpiTile(
                      label: 'Зээлээр гарсан',
                      value: formatMoney(s.credit),
                      caption: '${s.creditCount} захиалга',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Миний авлага',
                subtitle: 'Бүх хугацааны дүн — дээрх хугацааны шүүлтээс хамаарахгүй',
                actions: [TextButton(onPressed: widget.onReceivables, child: const Text('Дэлгэрэнгүй'))],
                child: Column(
                  children: [
                    AccRowLite('Тооцоо авагдсан', formatMoney(collected), 'зээлээс төлөгдсөн'),
                    AccRowLite(
                      'Үлдэгдэл авлага',
                      formatMoney(open.fold<num>(0, (a, r) => a + toNum(r['outstanding']))),
                      '${open.length} дэлгүүр',
                    ),
                    // ⚠ Хэтэрсэн авлага БАЙХГҮЙ үед улаанаар тэмдэглэхгүй.
                    AccRowLite(
                      'Хугацаа хэтэрсэн',
                      formatMoney(overdue.fold<num>(0, (a, r) => a + toNum(r['outstanding']))),
                      '${overdue.length} дэлгүүр',
                      warn: overdue.isNotEmpty,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Сар бүрийн борлуулалт',
                subtitle:
                    'Сүүлийн 6 сарын цэвэр захиалгын дүн · ${formatMoney(months.fold<num>(0, (a, e) => a + e.$2))}',
                child: Column(
                  children: [
                    for (final (month, amount) in months)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(_monthNames[month.month - 1], style: const TextStyle(color: AppColors.muted)),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: amount / maxMonth,
                                  minHeight: 12,
                                  backgroundColor: const Color(0xFFEFF3F8),
                                  color: const Color(0xFF178A5C),
                                ),
                              ),
                            ),
                            SizedBox(width: 100, child: Text(formatMoney(amount), textAlign: TextAlign.right)),
                          ],
                        ),
                      ),
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

class AccRowLite extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final bool warn;
  const AccRowLite(this.label, this.value, this.caption, {super.key, this.warn = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(caption, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, color: warn ? AppColors.danger : AppColors.text),
        ),
      ],
    ),
  );
}

// ── Буцаалт (бүх дэлгүүр) ───────────────────────────────────────────────────
class ReturnsPage extends StatefulWidget {
  final SellerController controller;
  const ReturnsPage({super.key, required this.controller});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  List<Json>? _rows;
  String? _error;
  DateRange _range = DateRange.preset(RangePreset.today);
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = jsonList(await widget.controller.api.get('/orders/my-return-items'));
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = SellerController.errorText(e, 'Татахад алдаа гарлаа.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = (_rows ?? const <Json>[]).where((r) => _range.contains(r['createdAt'])).toList();
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? all
        : all
              .where(
                (r) =>
                    '${r['storeName'] ?? ''} ${r['productName'] ?? ''} ${r['barcode'] ?? ''}'.toLowerCase().contains(q),
              )
              .toList();
    final empty = all.isNotEmpty
        ? 'Хайлтад тохирох буцаалт алга.'
        : (_rows ?? const []).isNotEmpty
        ? 'Энэ хугацаанд буцаалт алга.'
        : 'Одоогоор буцаалт алга.';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: KpiTile(label: 'Нийт буцаалт', value: '${all.length}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KpiTile(
                  label: 'Нийт дүн',
                  value: formatMoney(all.fold<num>(0, (a, r) => a + toNum(r['lineTotal']))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Дэлгүүр, бараагаар хайх...',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            EmptyState(_error!)
          else if (_rows == null)
            const LoadingState('Ачаалж байна…')
          else if (rows.isEmpty)
            EmptyState(empty)
          else
            for (final r in rows) ReturnItemCard(row: r, showStore: true),
        ],
      ),
    );
  }
}

// ── Урамшуулал ──────────────────────────────────────────────────────────────
class PromotionsPage extends StatefulWidget {
  final SellerController controller;
  const PromotionsPage({super.key, required this.controller});

  @override
  State<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends State<PromotionsPage> {
  List<Json>? _promos;
  bool _promoError = false;
  List<Json>? _orders;
  String? _ordersError;
  DateRange _range = DateRange.preset(RangePreset.today);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.controller.api;
    try {
      final promos = jsonList(await api.get('/promotions'))
          .where((p) => p['active'] == true && toNum(p['percent']) > 0)
          .toList();
      if (mounted) {
        setState(() {
          _promos = promos;
          _promoError = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _promoError = true);
    }
    try {
      final rows = jsonList(await api.get('/promotions/orders'));
      if (mounted) {
        setState(() {
          _orders = rows;
          _ordersError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _ordersError = SellerController.errorText(e, 'Татахад алдаа гарлаа.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    const payLabel = {'cash': 'Бэлэн', 'transfer': 'Данс', 'credit': 'Зээл'};
    final source = _orders ?? const <Json>[];
    // Хугацаа нь settledAt-аар.
    final list = source.where((r) => _range.contains(r['settledAt'])).toList();
    final empty = source.isNotEmpty
        ? 'Энэ хугацаанд хөнгөлөлт эдэлсэн захиалга алга.'
        : 'Одоогоор хөнгөлөлт эдэлсэн захиалга алга.';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_promoError)
            const EmptyState('Урамшуулал ачаалахад алдаа гарлаа.')
          else if (_promos == null)
            const LoadingState('Ачаалж байна…')
          else if (_promos!.isEmpty)
            const SectionCard(
              title: 'Урамшуулал',
              child: Text('Одоогоор идэвхтэй урамшуулал алга.', style: TextStyle(color: AppColors.muted)),
            )
          else
            for (final p in _promos!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SectionCard(
                  title: '${p['name'] ?? ''}',
                  actions: [
                    Tag('Идэвхтэй · −${p['percent']}%', color: AppColors.success, background: AppColors.successSoft),
                  ],
                  child: Text(
                    str(p['description']) ??
                        'Зээлээс бусад (бэлэн/данс) төлбөрөөр бүрэн тооцвол нийт дүнгээс −${p['percent']}% хөнгөлнө.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: KpiTile(label: 'Хөнгөлсөн захиалга', value: '${list.length}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KpiTile(
                  label: 'Нийт хөнгөлөлт',
                  value: formatMoney(list.fold<num>(0, (a, r) => a + toNum(r['discountAmount']))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
          const SizedBox(height: 12),
          if (_ordersError != null)
            EmptyState(_ordersError!)
          else if (_orders == null)
            const LoadingState('Ачаалж байна…')
          else if (list.isEmpty)
            EmptyState(empty)
          else
            for (final r in list)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text('${r['storeName'] ?? '-'}'),
                  subtitle: Text(
                    [
                      formatDateTime(r['settledAt']),
                      '${r['promotionName'] ?? '-'}${r['paymentMethod'] != null ? ' (${payLabel[r['paymentMethod']] ?? r['paymentMethod']})' : ''}',
                      'Нийт ${formatMoney(toNum(r['totalAmount']))} · Төлсөн ${formatMoney(toNum(r['paidAmount']))}',
                    ].join('\n'),
                  ),
                  trailing: Text(
                    '−${formatMoney(toNum(r['discountAmount']))}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
