import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/ui.dart';
import 'seller_logic.dart';

export '../factory/factory_widgets.dart' show ExpandTile, AccRow;

/// Алдааг мөрөнд бичихээс гадна попап цонхоор гаргана — утсан дээр мөр нь
/// ихэвчлэн дэлгэцээс гадуур байдаг (web-ийн popupError).
Future<void> alertError(BuildContext context, String text, {String? title}) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: title == null ? null : Text(title),
    content: Text(text),
    actions: [FilledButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Ойлголоо'))],
  ),
);

Widget statusTag(Object? status) => switch (status) {
  'delivered' => const Tag('Хүргэсэн', color: AppColors.success, background: AppColors.successSoft),
  'returned' => const Tag('Буцаагдсан', color: AppColors.danger, background: AppColors.dangerSoft),
  _ => const Tag.warning('Хүргээгүй'),
};

Widget lockTag(Json order) => order['locked'] == true
    ? const Tag('Түгжигдсэн', color: AppColors.danger, background: AppColors.dangerSoft)
    : const Tag('Түгжээгүй', color: AppColors.success, background: AppColors.successSoft);

Widget recvStatusTag(Object? status, [int count = 0]) {
  final n = count > 1 ? ' $count' : '';
  return switch (status) {
    'overdue' => Tag('Хэтэрсэн$n', color: AppColors.danger, background: AppColors.dangerSoft),
    'warning' => Tag.warning('Ойртсон$n'),
    'paid' => const Tag('Төлсөн'),
    _ => Tag('Хэвийн$n', color: AppColors.success, background: AppColors.successSoft),
  };
}

String shortId(Object? id) {
  final s = '${id ?? ''}';
  return (s.length > 8 ? s.substring(0, 8) : s).toUpperCase();
}

/// Мөнгөн нүд: 0 бол «—».
String moneyOrDash(Object? v) => toNum(v) > 0 ? formatMoney(toNum(v)) : '—';

/// Жижиг гарчиг + утга бүхий мөр (дэлгүүрийн мэдээлэлд).
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// + / − бүхий тоо оруулагч. [floor] нь доод хязгаар (ганц нэгжид 1, хоёр нэгжид 0).
class QtyStepper extends StatefulWidget {
  final int value;
  final int floor;
  final ValueChanged<int> onChanged;
  final String? label;
  const QtyStepper({super.key, required this.value, required this.onChanged, this.floor = 1, this.label});

  @override
  State<QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<QtyStepper> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant QtyStepper old) {
    super.didUpdateWidget(old);
    if (int.tryParse(_c.text) != widget.value) _c.text = '${widget.value}';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(int v) {
    final next = v < widget.floor ? widget.floor : v;
    _c.text = '$next';
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          SizedBox(
            width: 64,
            child: Text(widget.label!, style: const TextStyle(color: AppColors.muted)),
          ),
        IconButton.outlined(
          onPressed: () => _set(widget.value - 1),
          icon: const Icon(Icons.remove, size: 18),
          tooltip: 'Хасах',
        ),
        SizedBox(
          width: 64,
          child: TextField(
            controller: _c,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            onChanged: (s) {
              final v = int.tryParse(s);
              if (v != null) widget.onChanged(v < widget.floor ? widget.floor : v);
            },
          ),
        ),
        IconButton.outlined(
          onPressed: () => _set(widget.value + 1),
          icon: const Icon(Icons.add, size: 18),
          tooltip: 'Нэмэх',
        ),
      ],
    );
  }
}

/// Хайлтын талбар.
class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const SearchField({super.key, required this.hint, required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: hint),
    onChanged: onChanged,
  );
}
