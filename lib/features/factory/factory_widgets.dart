import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/ui.dart';

/// «10+4 ш» — батлагдсан + шараар батлагдаагүй хэсэг. Батлагдаагүй 0 бол «10 ш».
class QtyLabel extends StatelessWidget {
  final int locked;
  final int unlocked;
  final String unit;
  final TextStyle? style;
  const QtyLabel(this.locked, this.unlocked, this.unit, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: formatQty(locked)),
          if (unlocked > 0)
            TextSpan(
              text: '+${formatQty(unlocked)}',
              style: const TextStyle(color: AppColors.warning, fontStyle: FontStyle.italic),
            ),
          TextSpan(text: ' $unit'),
        ],
      ),
      semanticsLabel: unlocked > 0
          ? '${formatQty(locked)} $unit батлагдсан, ${formatQty(unlocked)} $unit батлагдаагүй'
          : null,
    );
  }
}

/// Бэлтгэлийн явц «12/20» эсвэл «20/20 бэлэн».
class ProgressChip extends StatelessWidget {
  final int done;
  final int need;
  final String doneSuffix;
  const ProgressChip(this.done, this.need, {super.key, this.doneSuffix = ' бэлэн'});

  @override
  Widget build(BuildContext context) {
    if (need <= 0) return const SizedBox.shrink();
    final d = done.clamp(0, need);
    final full = d >= need;
    return Tag(
      '${formatQty(d)}/${formatQty(need)}${full ? doneSuffix : ''}',
      color: full ? AppColors.success : AppColors.muted,
      background: full ? AppColors.successSoft : const Color(0xFFF1F4F9),
    );
  }
}

Widget dayTag(String? iso) {
  final day = orderDay(iso);
  if (day == null) return const SizedBox.shrink();
  return day.old ? Tag.warning(day.label) : Tag(day.label);
}

Widget zoneTag(String? zone) => zone == null
    ? const Tag('Бүсгүй', color: AppColors.muted)
    : Tag(zone, color: AppColors.brand, background: const Color(0xFFE7F3EE));

/// Нээгддэг/хаагддаг мөр. Нээлттэй эсэхийг ДУУДАГЧ хадгална (жагсаалт дахин
/// зурагдахад хаагдахгүй байлгахын тулд).
class ExpandTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool open;
  final ValueChanged<bool> onToggle;
  final List<Widget> children;
  final Color? tint;

  const ExpandTile({
    super.key,
    required this.title,
    required this.open,
    required this.onToggle,
    required this.children,
    this.subtitle,
    this.trailing,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: tint ?? AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => onToggle(!open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle.merge(
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          child: title,
                        ),
                        if (subtitle != null) ...[const SizedBox(height: 3), subtitle!],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    // ⚠ Нарийн утсан дээр баруун хэсэг гарчгийг шахаж overflow
                    //   болохгүйн тулд жижигрүүлнэ (тасдахгүй — тоо бүтэн харагдана).
                    Flexible(
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: trailing),
                    ),
                  ],
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Container(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Задаргааны мөр: нэр — утга.
class AccRow extends StatelessWidget {
  final String label;
  final Widget value;
  final bool warn;
  const AccRow(this.label, this.value, {super.key, this.warn = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: warn ? AppColors.warning : AppColors.text)),
        ),
        const SizedBox(width: 8),
        value,
      ],
    ),
  );
}

/// Бэлдсэн тоо оруулах талбар + «бүгдийг бэлдсэн» товч.
/// ⚠ Талбарт бичиж байх зуур гаднаас дахин зурагдвал утга ДАРАГДАХГҮЙ
///   (фокустай үед гаднын утгыг үл тоомсорлоно) — web дээр «бичиж байсан тоо
///   замхардаг» асуудал байсан.
class PrepControl extends StatefulWidget {
  final int done;
  final int need;
  final Widget ofLabel;
  final bool disabled;
  final ValueChanged<int> onCommit;
  final VoidCallback onToggle;
  final String semanticName;

  const PrepControl({
    super.key,
    required this.done,
    required this.need,
    required this.ofLabel,
    required this.onCommit,
    required this.onToggle,
    required this.semanticName,
    this.disabled = false,
  });

  @override
  State<PrepControl> createState() => _PrepControlState();
}

class _PrepControlState extends State<PrepControl> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.done}');
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant PrepControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _controller.text != '${widget.done}') {
      _controller.text = '${widget.done}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final value = int.tryParse(_controller.text.trim()) ?? 0;
    final clamped = value.clamp(0, widget.need);
    if ('$clamped' != _controller.text) _controller.text = '$clamped';
    if (clamped != widget.done) widget.onCommit(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.done >= widget.need && widget.need > 0;
    final partial = widget.done > 0 && !full;
    final color = full
        ? AppColors.success
        : partial
        ? AppColors.warning
        : AppColors.border;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 54,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: !widget.disabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _commit(),
            style: const TextStyle(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: color, width: full || partial ? 1.6 : 1),
              ),
            ),
            // Дэлгэц уншигчид: «Бараа — Түгээгч — бэлдсэн тоо».
            onTapOutside: (_) => _focus.unfocus(),
          ),
        ),
        const SizedBox(width: 6),
        DefaultTextStyle.merge(
          style: const TextStyle(color: AppColors.muted),
          child: widget.ofLabel,
        ),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          toggled: full,
          label: '${widget.semanticName} — бүгдийг бэлдсэн',
          child: InkResponse(
            onTap: widget.disabled ? null : widget.onToggle,
            radius: 22,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: full ? AppColors.success : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: full ? AppColors.success : AppColors.border, width: 1.4),
              ),
              child: Icon(Icons.check, size: 20, color: full ? Colors.white : AppColors.border),
            ),
          ),
        ),
      ],
    );
  }
}
