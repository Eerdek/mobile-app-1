import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/ui.dart';
import '../../printing/ble_printer.dart';
import 'delivery_controller.dart';
import 'delivery_orders.dart';
import 'delivery_tabs.dart';

/// Түгээгч — GeoGate дотор нээгдэнэ (GPS зөвшөөрөлгүй бол ашиглахгүй).
/// Доод цэс web-ийн утасны цэстэй ижил; Тайлан нь самбар болон толгойн товчоор.
class DeliveryShell extends StatefulWidget {
  final ApiClient api;
  final Session session;
  const DeliveryShell({super.key, required this.api, required this.session});

  @override
  State<DeliveryShell> createState() => _DeliveryShellState();
}

class _DeliveryShellState extends State<DeliveryShell> {
  late final DeliveryController _c = DeliveryController(widget.api, widget.session.user?.id ?? 'me');
  int _index = 0;
  final Set<int> _visited = {0};

  static const _titles = [
    ('Хянах самбар', 'Өнөөдрийн хүргэлтийн тойм'),
    ('Захиалгын жагсаалт', 'Танд оноогдсон, хүлээгдэж буй хүргэлтүүд'),
    ('Маршрут', 'Хүргэх цэгүүд, газрын зураг'),
    ('Ачаа хүлээн авах', 'Үйлдвэрээс гарсан ачааг ангиллаар нь тоолж хүлээн авна'),
    ('Хүргэлтийн түүх', 'Гүйцэтгэсэн болон буцаасан хүргэлтүүд'),
  ];

  @override
  void initState() {
    super.initState();
    _c.loadAll();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  void _openReport() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DeliveryReportScreen(controller: _c)),
      );

  Future<void> _account() async {
    final user = widget.session.user;
    final printerName = await BlePrinter.instance.savedPrinterName();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.brand,
              child: Text(user?.initial ?? 'Т', style: const TextStyle(color: Colors.white)),
            ),
            title: Text(user?.displayName ?? 'Түгээгч'),
            subtitle: const Text('Түгээлтийн эрх'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Тайлан'),
            onTap: () {
              Navigator.of(sheet).pop();
              _openReport();
            },
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Принтер'),
            subtitle: Text(printerName ?? 'Сонгоогүй — анх хэвлэхэд сонгоно'),
            trailing: printerName == null
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
        ]),
      ),
    );
  }

  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      0 => DeliveryDashboardTab(controller: _c, onOpenReport: _openReport),
      1 => DeliveryOrdersTab(controller: _c),
      2 => DeliveryRouteTab(controller: _c),
      3 => DeliveryReceiveTab(controller: _c),
      _ => DeliveryHistoryTab(controller: _c, courierName: widget.session.user?.displayName ?? '—'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _titles[_index];
    final user = widget.session.user;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(children: [
          Image.asset('assets/images/akifoods-logo.png', width: 40, height: 34, fit: BoxFit.contain),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        actions: [
          IconButton(tooltip: 'Тайлан', icon: const Icon(Icons.receipt_long_outlined), onPressed: _openReport),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkResponse(
              onTap: _account,
              radius: 22,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.brand,
                child: Text(user?.initial ?? 'Т', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Самбар'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Захиалга'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Маршрут'),
          NavigationDestination(icon: Icon(Icons.inventory_outlined), selectedIcon: Icon(Icons.inventory), label: 'Хүлээн авах'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Түүх'),
        ],
      ),
    );
  }
}
