import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/ui.dart';
import '../../printing/ble_printer.dart';
import 'my_orders_page.dart';
import 'placement_page.dart';
import 'receivables_page.dart';
import 'seller_controller.dart';
import 'simple_pages.dart';
import 'store_picker.dart';
import 'store_workspace.dart';

enum SellerPage { orders, customers, returns, receivables, dashboard, promotions, placement }

const Map<SellerPage, (String, String)> _meta = {
  SellerPage.dashboard: ('Самбар', 'Борлуулалтын үзүүлэлт ба сарын график'),
  SellerPage.orders: ('Захиалга', 'Миний бүртгэсэн бүх захиалга — түгжигдээгүйг засах боломжтой'),
  SellerPage.customers: ('Харилцагч', 'Дэлгүүр сонгож, бүртгэлтэй бараанаас захиалга авна'),
  SellerPage.promotions: ('Урамшуулал', 'Урамшуулал болон хөнгөлөлтийн удирдлага'),
  SellerPage.returns: ('Буцаалт', 'Буцаалтын хүсэлт болон түүх'),
  SellerPage.placement: ('Барааны өрөлт', 'Барааны өрөлт, үлдэгдлийн хөдөлгөөн'),
  SellerPage.receivables: ('Авлага', 'Хүргэгдсэн захиалгаар тооцсон дэлгүүрийн авлага'),
};

// Доод цэсийн 4 үндсэн хуудас + «Бусад».
const List<SellerPage> _navPages = [
  SellerPage.orders,
  SellerPage.customers,
  SellerPage.returns,
  SellerPage.receivables,
];

/// Борлуулагч (seller) болон ахлах борлуулагч (senior) — GeoGate дотор нээгдэнэ.
class SellerShell extends StatefulWidget {
  final ApiClient api;
  final Session session;
  const SellerShell({super.key, required this.api, required this.session});

  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> with WidgetsBindingObserver {
  late final SellerController _c = SellerController(widget.api, widget.session.user!);
  // Борлуулагч анх «Захиалга» хуудсанд буудаг.
  SellerPage _page = SellerPage.orders;
  final Set<SellerPage> _visited = {SellerPage.orders};
  // Буцаалт/урамшуулал хуудсыг web шиг ОРОХ БҮРД дахин ачаална (key солигдоход initState дахин).
  final Map<SellerPage, int> _reloads = {};
  int _storeSession = 0;
  DateTime _productsAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onController);
    _c.loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onController);
    _c.dispose();
    super.dispose();
  }

  // Дэлгүүр аль ч хуудаснаас сонгогдоход (авлага, захиалгын засах/хуулах)
  // ажлын талбар байрлах «Харилцагч» хуудас руу шилжинэ.
  void _onController() {
    if (_c.storeSession == _storeSession) return;
    _storeSession = _c.storeSession;
    if (_c.selectedStore != null && _page != SellerPage.customers) _go(SellerPage.customers);
  }

  // Апп нээлттэй удаан байхад барааны үнэ/идэвх өөрчлөгдөж болно — буцаж ороход
  // минутад нэгээс олонгүй каталогийг чимээгүй шинэчилнэ (web-тэй адил).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (DateTime.now().difference(_productsAt) < const Duration(minutes: 1)) return;
    _productsAt = DateTime.now();
    _c.loadProducts().catchError((_) {});
  }

  void _go(SellerPage page) {
    setState(() {
      if (page == SellerPage.returns || page == SellerPage.promotions) {
        _reloads[page] = (_reloads[page] ?? 0) + 1;
      }
      _page = page;
      _visited.add(page);
    });
  }

  Future<void> _refresh() async {
    _productsAt = DateTime.now();
    setState(() {
      _reloads[SellerPage.returns] = (_reloads[SellerPage.returns] ?? 0) + 1;
      _reloads[SellerPage.promotions] = (_reloads[SellerPage.promotions] ?? 0) + 1;
    });
    await _c.loadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Мэдээлэл шинэчлэгдлээ.')));
  }

  Future<void> _more() async {
    final printer = await BlePrinter.instance.savedPrinterName();
    if (!mounted) return;
    final user = widget.session.user;
    final picked = await showModalBottomSheet<SellerPage>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.brand,
                child: Text(user?.initial ?? 'Б', style: const TextStyle(color: Colors.white)),
              ),
              title: Text(user?.displayName ?? 'Борлуулагч'),
              subtitle: Text(_c.isSenior ? 'Ахлах борлуулагчийн эрх' : 'Борлуулагчийн эрх'),
            ),
            const Divider(),
            for (final (page, icon) in const [
              (SellerPage.dashboard, Icons.dashboard_outlined),
              (SellerPage.promotions, Icons.local_offer_outlined),
              (SellerPage.placement, Icons.photo_camera_outlined),
            ])
              ListTile(leading: Icon(icon), title: Text(_meta[page]!.$1), onTap: () => Navigator.of(sheet).pop(page)),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Принтер'),
              subtitle: Text(printer ?? 'Сонгоогүй — анх хэвлэхэд сонгоно'),
              trailing: printer == null
                  ? null
                  : TextButton(
                      onPressed: () async {
                        await BlePrinter.instance.forgetPrinter();
                        if (sheet.mounted) Navigator.of(sheet).pop();
                      },
                      child: const Text('Мартах'),
                    ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Системээс гарах', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.of(sheet).pop();
                widget.session.clear();
              },
            ),
          ],
        ),
      ),
    );
    if (picked != null) _go(picked);
  }

  Widget _body(SellerPage page) {
    if (!_visited.contains(page)) return const SizedBox.shrink();
    return switch (page) {
      SellerPage.orders => MyOrdersPage(controller: _c, onOpenWorkspace: () => _go(SellerPage.customers)),
      SellerPage.customers => ListenableBuilder(
        listenable: _c,
        builder: (context, _) => _c.selectedStore == null
            ? StorePicker(controller: _c)
            : StoreWorkspace(controller: _c, onOrderDone: () => _go(SellerPage.orders)),
      ),
      SellerPage.returns => ReturnsPage(key: ValueKey('ret:${_reloads[page]}'), controller: _c),
      SellerPage.receivables => ReceivablesPage(controller: _c),
      SellerPage.dashboard => DashboardPage(
        controller: _c,
        onNewOrder: () => _go(SellerPage.customers),
        onReceivables: () => _go(SellerPage.receivables),
      ),
      SellerPage.promotions => PromotionsPage(key: ValueKey('promo:${_reloads[page]}'), controller: _c),
      SellerPage.placement => PlacementPage(controller: _c),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _meta[_page]!;
    final navIndex = _navPages.indexOf(_page);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Image.asset('assets/images/akifoods-logo.png', width: 40, height: 34, fit: BoxFit.contain),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [IconButton(tooltip: 'Шинэчлэх', icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: IndexedStack(
        index: SellerPage.values.indexOf(_page),
        children: [for (final p in SellerPage.values) _body(p)],
      ),
      floatingActionButton: _page == SellerPage.orders
          ? FloatingActionButton.extended(
              onPressed: () => _go(SellerPage.customers),
              icon: const Icon(Icons.add),
              label: const Text('Шинэ захиалга'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        // «Бусад» хуудас (самбар/урамшуулал/өрөлт) нээлттэй үед «Бусад» тодорно.
        selectedIndex: navIndex < 0 ? _navPages.length : navIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => i < _navPages.length ? _go(_navPages[i]) : _more(),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Захиалга',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Харилцагч',
          ),
          NavigationDestination(icon: Icon(Icons.undo_outlined), selectedIcon: Icon(Icons.undo), label: 'Буцаалт'),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Авлага',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Бусад'),
        ],
      ),
    );
  }
}
