// Баримт/хуудасны зохиомж — 576 цэгийн (72мм) өргөнд. web-ийн bt-print.js-ийн
// RECEIPT_CSS-ийн Flutter хувилбар: 1 логик пиксел = 1 принтерийн цэг.
//
// ⚠ Энэ widget-ийг ЯГ 576 өргөнтэй, утасны фонтын томруулалтгүйгээр
//   (TextScaler.noScaling) зурна — эс бөгөөс хэрэглэгчийн «том үсэг»
//   тохиргоо цаасан дээрх мөрийг эвдэнэ. ReceiptFrame үүнийг хангана.
import 'package:flutter/material.dart';

import 'escpos.dart';

const TextStyle receiptBase = TextStyle(
  fontFamily: 'AkiReceiptMono',
  fontFamilyFallback: ['AkiReceiptMonoCyrl'],
  fontSize: 20,
  height: 1.12,
  color: Colors.black,
  fontWeight: FontWeight.w400,
  // ⚠ Лигатур хаалттай — web-ийн .r-doc-той ижил.
  fontFeatures: [FontFeature.disable('liga'), FontFeature.disable('clig')],
  letterSpacing: 0,
);

const TextStyle receiptBold = TextStyle(fontWeight: FontWeight.w700);

// ⚠ Баримтын фонтын subset-д «·» (U+00B7) БАЙХГҮЙ — web дээр системийн
//   фонтоос авдаг байсан тул өргөн нь зөрдөг байв, энд бол ☒ болно.
//   Subset-д байдаг «•» (U+2022)-ээр солино.
String receiptText(String s) => s.replaceAll('·', '•');

/// Баримтын хүрээ: цагаан дэвсгэр, 576 өргөн, томруулалтгүй.
class ReceiptFrame extends StatelessWidget {
  final List<Widget> children;
  const ReceiptFrame({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: DefaultTextStyle(
        style: receiptBase,
        child: Container(
          width: dotsPerLine.toDouble(),
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class RTitle extends StatelessWidget {
  final String text;
  const RTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: 1),
    ),
  );
}

/// `.r-line` — зүүн талд шошго, баруун талд утга. Багтахгүй бол утга дараагийн
/// мөрөнд бууна (CSS flex-wrap).
class RLine extends StatelessWidget {
  final InlineSpan label;
  final InlineSpan value;
  final bool strong;

  const RLine(this.label, this.value, {super.key, this.strong = false});

  factory RLine.text(String label, String value, {bool strong = false}) => RLine(
    TextSpan(text: receiptText(label)),
    TextSpan(text: receiptText(value)),
    strong: strong,
  );

  @override
  Widget build(BuildContext context) {
    final style = strong ? receiptBold : null;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 10,
      children: [
        Text.rich(TextSpan(style: style, children: [label])),
        Text.rich(
          TextSpan(style: style, children: [value]),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }
}

/// `.r-sep` — 2px тасархай зураас.
class RSep extends StatelessWidget {
  const RSep({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 3),
    child: SizedBox(height: 2, child: CustomPaint(painter: _DashPainter())),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    const dash = 6.0;
    const gap = 4.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 1), Offset((x + dash).clamp(0, size.width), 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// `.r-zone` / `.r-total-head` — хүрээтэй, төвд, ТОМ үсгийн толгой.
class RHead extends StatelessWidget {
  final String text;
  const RHead(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 2),
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
    decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
    child: Text(
      receiptText(text).toUpperCase(),
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
    ),
  );
}

class RNote extends StatelessWidget {
  final String text;
  const RNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(receiptText(text), style: const TextStyle(fontSize: 18)),
  );
}

/// Гараар тэмдэглэх нүд. ⚠ Юникод (☐) биш — 72мм фонтод байхгүй бол «?»
/// болж хэвлэгддэг. Дүүргэсэн (`on`) = аппад бэлдэж дууссан мөр.
WidgetSpan tickBox({bool on = false}) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Container(
    margin: const EdgeInsets.only(left: 6),
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: on ? Colors.black : null,
      border: Border.all(color: Colors.black, width: 1),
    ),
  ),
);
