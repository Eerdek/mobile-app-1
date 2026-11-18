import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/ui.dart';
import '../../printing/ble_printer.dart';
import 'factory_controller.dart';
import 'history_tab.dart';
import 'prepare_tab.dart';
import 'stock_tab.dart';
import 'techcards_tab.dart';
import 'zones_tab.dart';

class FactoryShell extends StatefulWidget {
  final ApiClient api;
  final Session session;
  const FactoryShell({super.key, required this.api, required this.session});

  @override
  State<FactoryShell> createState() => _FactoryShellState();
}

class _FactoryShellState extends State<FactoryShell> {
  late final FactoryController _factory = FactoryController(widget.api);
  late final StockStore _stock = StockStore(widget.api);
  int _index = 0;
  // Таб бүр анх нээгдэхдээ л үүснэ; дараа нь төлөвөө хадгална.
  final Set<int> _visited = {0};
  // Дахин орох бүрд тухайн таб өгөгдлөө шинэчилнэ (web-тэй адил).
  final List<ValueNotifier<int>> _revisit = List.generate(5, (_) => ValueNotifier(0));

  static const _titles = [
    ('Бэлтгэх бараа', 'Хүргэгдээгүй захиалгын нэгтгэл — түгээгч ирж авна'),
    ('Барааны үлдэгдэл', 'Бэлэн бараа, түүхий эд, шошгоны үлдэгдэл'),
    ('Бэлтгэх заавар', 'Бараа тус бүрийн орц ба бэлтгэх дараалал'),
    ('Бүсийн зураглал', 'Өнөөдөр бэлдэх ачаа аль бүсэд байгаа вэ'),
    ('Гарсан барааны түүх', 'Хүргэгдсэн захиалгын барааны нэгтгэл'),
  ];

  @override
  void dispose() {
    for (final n in _revisit) {
      n.dispose();
    }
    _factory.dispose();
    _stock.dispose();
    super.dispose();
  }

  void _select(int i) {
    final again = _visited.contains(i) && i != _index;
    setState(() {
      _index = i;
      _visited.add(i);
    });
    if (again && i != 0) _revisit[i].value++;
    // Борлуулагчид өдөржин захиалга нэмдэг — бэлтгэл рүү ормогц шинэчилнэ.
    if (i == 0) _factory.loadPrepare();
  }

  Future<void> _account() async {
    final user = widget.session.user;
    final printerName = await BlePrinter.instance.savedPrinterName();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.brand,
                child: Text(user?.initial ?? 'Ү', style: const TextStyle(color: Colors.white)),
              ),
              title: Text(user?.displayName ?? 'Үйлдвэр'),
              subtitle: const Text('Үйлдвэрийн эрх'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Принтер'),
              subtitle: Text(printerName ?? 'Сонгоогүй — анх хэвлэхэд сонгоно'),
              trailing: printerName == null
                  ? null
                  : TextButton(
                      onPressed: () async {
                        await BlePrinter.instance.forgetPrinter();
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Мартах'),
                    ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Системээс гарах', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.session.clear();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      0 => PrepareTab(controller: _factory),
      1 => StockTab(store: _stock, revisit: _revisit[1]),
      2 => TechCardsTab(stock: _stock, revisit: _revisit[2]),
      3 => ZonesTab(controller: _factory, revisit: _revisit[3]),
      _ => HistoryTab(api: widget.api, revisit: _revisit[4]),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _titles[_index];
    final user = widget.session.user;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/images/akifoods-logo.png', width: 40, height: 34, fit: BoxFit.contain),
            ),
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkResponse(
              onTap: _account,
              radius: 22,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.brand,
                child: Text(
                  user?.initial ?? 'Ү',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: [for (var i = 0; i < 5; i++) _tab(i)]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Бэлтгэл',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Үлдэгдэл',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Заавар',
          ),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Бүс'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Түүх'),
        ],
      ),
    );
  }
}
