import 'package:flutter/material.dart';

import 'format.dart';

// Стандарт хугацааны хүрээ (бүх аппад ижил): Бүгд / Өнөөдөр / 7 хоног / Энэ сар
// + эхлэх–дуусах огноо. null = тухайн талаас хязгааргүй.
enum RangePreset { all, today, week, month }

class DateRange {
  final DateTime? from;
  final DateTime? to;
  const DateRange(this.from, this.to);

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  factory DateRange.preset(RangePreset p) => switch (p) {
        RangePreset.all => const DateRange(null, null),
        RangePreset.today => DateRange(_today, _today),
        RangePreset.week => DateRange(_today.subtract(const Duration(days: 6)), _today),
        RangePreset.month => DateRange(DateTime(_today.year, _today.month, 1), _today),
      };

  RangePreset? get preset {
    for (final p in RangePreset.values) {
      final r = DateRange.preset(p);
      if (r.from == from && r.to == to) return p;
    }
    return null;
  }

  bool get isToday => preset == RangePreset.today;
  bool get isSingleDay => from != null && from == to;

  /// Утга хүрээнд багтах эсэх — ЛОКАЛ өдрөөр.
  bool contains(Object? iso) {
    if (from == null && to == null) return true;
    final d = parseDate(iso);
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    if (from != null && day.isBefore(from!)) return false;
    if (to != null && day.isAfter(to!)) return false;
    return true;
  }

  /// Сервер рүү [from, to) ISO хязгаар.
  String? get fromIso => from?.toUtc().toIso8601String();
  String? get toIsoExclusive => to?.add(const Duration(days: 1)).toUtc().toIso8601String();

  String get label {
    String dot(DateTime d) => ymd(d).replaceAll('-', '.');
    if (from != null && to != null && from == to) return '${from!.year} оны ${from!.month} сарын ${from!.day}';
    if (from != null && to != null) return '${dot(from!)} – ${dot(to!)}';
    if (from != null) return '${dot(from!)}-с хойш';
    if (to != null) return '${dot(to!)} хүртэл';
    return 'Бүх хугацаа';
  }
}

const Map<RangePreset, String> _presetLabels = {
  RangePreset.all: 'Бүгд',
  RangePreset.today: 'Өнөөдөр',
  RangePreset.week: '7 хоног',
  RangePreset.month: 'Энэ сар',
};

class DateRangeBar extends StatelessWidget {
  final DateRange value;
  final ValueChanged<DateRange> onChanged;
  final List<RangePreset> presets;

  const DateRangeBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.presets = const [RangePreset.all, RangePreset.today, RangePreset.week, RangePreset.month],
  });

  Future<void> _pick(BuildContext context, bool from) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? value.from : value.to) ?? now,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    var f = from ? picked : value.from;
    var t = from ? value.to : picked;
    // Буруу дараалалтай бол солино.
    if (f != null && t != null && f.isAfter(t)) (f, t) = (t, f);
    onChanged(DateRange(f, t));
  }

  @override
  Widget build(BuildContext context) {
    final active = value.preset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in presets)
            ChoiceChip(
              label: Text(_presetLabels[p]!),
              selected: active == p,
              onSelected: (_) => onChanged(DateRange.preset(p)),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(context, true),
              icon: const Icon(Icons.event, size: 18),
              label: Text(value.from == null ? 'Эхлэх' : ymd(value.from!)),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(context, false),
              icon: const Icon(Icons.event, size: 18),
              label: Text(value.to == null ? 'Дуусах' : ymd(value.to!)),
            ),
          ),
        ]),
      ],
    );
  }
}
