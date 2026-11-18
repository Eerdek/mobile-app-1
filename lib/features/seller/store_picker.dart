import 'package:flutter/material.dart';

import '../../core/ui.dart';
import 'seller_controller.dart';
import 'seller_logic.dart';
import 'seller_widgets.dart';
import 'store_sheets.dart';

/// Дэлгүүр сонгох — гарагийн шүүлт (ЗӨВХӨН ажлын өдрүүд, анхдагч өнөөдөр),
/// хайлт, бүсийн зураг, шинэ дэлгүүр. Өнөөдрийн маршрутынх эхэнд.
class StorePicker extends StatefulWidget {
  final SellerController controller;
  const StorePicker({super.key, required this.controller});

  @override
  State<StorePicker> createState() => _StorePickerState();
}

class _StorePickerState extends State<StorePicker> {
  final Set<int> _days = {};
  bool _daysInit = false;
  String _query = '';

  SellerController get c => widget.controller;

  void _initDays() {
    // Анхдагч: өнөөдрийн гараг (ажлын өдөр бол); эс бөгөөс шүүлтгүй.
    if (_daysInit || !c.loaded) return;
    _daysInit = true;
    final today = jsDay();
    if (c.workDays.contains(today)) _days.add(today);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        _initDays();
        final stores = filterStores(c.stores, _query).where((s) => storeMatchesDays(s, _days)).toList()
          ..sort((a, b) => (isTodayStore(b) ? 1 : 0) - (isTodayStore(a) ? 1 : 0));
        final showCycle = c.cycleWeek != null && c.cycleZones.length > 1;
        final rest = c.cycleZones.where((z) => !c.activeZones.contains(z)).toList();
        return RefreshIndicator(
          onRefresh: () => c.refreshWith(() => Future.wait([c.loadStores(), c.loadSchedule()])),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              MessageBanner(c.message, onClose: () => c.setMessage(null)),
              // ⚠ Мөчлөг тохируулаагүй (эсвэл ганц бүстэй) бол самбар ОГТ харагдахгүй.
              if (showCycle)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFE7F3EE), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Мөчлөгийн ${c.cycleWeek}/${c.cycleWeeks}-р долоо хоног',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                      Text(
                        c.activeZones.isEmpty ? '— ээлжит бүс алга —' : c.activeZones.join(', '),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand),
                      ),
                      if (rest.isNotEmpty)
                        Text(
                          'Дараагийнх: ${rest.join(', ')}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('Бүгд'),
                        selected: _days.isEmpty,
                        onSelected: (_) => setState(_days.clear),
                      ),
                    ),
                    for (final d in dayOrder.where(c.workDays.contains))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            dayLabels[d]!,
                            style: TextStyle(fontWeight: d == jsDay() ? FontWeight.w800 : FontWeight.w500),
                          ),
                          selected: _days.contains(d),
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SearchField(hint: 'Нэр, код, утас, хаягаар хайх…', onChanged: (v) => setState(() => _query = v)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openZoneMap(context, c),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Зураг'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => openStoreForm(context, c),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Шинэ дэлгүүр'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!c.loaded && c.stores.isEmpty)
                const LoadingState('Дэлгүүрүүдийг ачаалж байна…')
              else if (stores.isEmpty)
                EmptyState(_days.isNotEmpty ? 'Сонгосон гарагт төлөвлөгдсөн дэлгүүр алга.' : 'Дэлгүүр олдсонгүй.')
              else
                for (final s in stores) _StoreCard(store: s, onTap: () => c.selectStore('${s['id']}')),
            ],
          ),
        );
      },
    );
  }
}

class _StoreCard extends StatelessWidget {
  final Json store;
  final VoidCallback onTap;
  const _StoreCard({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final today = isTodayStore(store);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: today ? AppColors.brand : AppColors.border, width: today ? 1.4 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              StoreImage(url: str(store['coverImageUrl']), size: 52),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${store['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (today) const Tag('Өнөөдөр', color: AppColors.brand, background: Color(0xFFE7F3EE)),
                        if (store['storeType'] == 'wholesale') const Tag('Бөөний'),
                        // Борлуулагчийн нэмсэн, админ хараахан шалгаагүй дэлгүүр.
                        if (store['reviewStatus'] == 'pending') const Tag.warning('Шалгаагүй'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${str(store['storeCode']) ?? '-'} · ${str(store['phone']) ?? ''}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                    if (str(store['address']) != null)
                      Text(
                        '${store['address']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class StoreImage extends StatelessWidget {
  final String? url;
  final double size;
  const StoreImage({super.key, required this.url, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xFFEFF3F8),
      child: Icon(Icons.storefront_outlined, color: AppColors.muted, size: size * 0.5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder
          : Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}
