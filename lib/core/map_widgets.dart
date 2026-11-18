import 'package:flutter/material.dart';

/// Газрын зургийн дугаартай дусал pin (28×36) — үйлдвэрийн бүсийн зураг,
/// түгээгчийн маршрут ижил. Marker-ийн alignment: Alignment.topCenter
/// (дуслын үзүүр координат дээр таарна).
class NumberPin extends StatelessWidget {
  final Color color;
  final int number;
  const NumberPin({super.key, required this.color, required this.number});

  @override
  Widget build(BuildContext context) {
    final label = '$number';
    return CustomPaint(
      size: const Size(28, 36),
      painter: NumberPinPainter(color),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: label.length > 2 ? 9.4 : 11.6,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }
}

class NumberPinPainter extends CustomPainter {
  final Color color;
  const NumberPinPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // web-ийн FACTORY_PIN_PATH-тай ижил дусал хэлбэр (28×36).
    final path = Path()
      ..moveTo(14, 0.9)
      ..cubicTo(6.8, 0.9, 1, 6.7, 1, 13.9)
      ..cubicTo(1, 23.1, 12.4, 33.7, 13.5, 34.6)
      ..cubicTo(13.8, 34.9, 14.2, 34.9, 14.5, 34.6)
      ..cubicTo(15.6, 33.7, 27, 23.1, 27, 13.9)
      ..cubicTo(27, 6.7, 21.2, 0.9, 14, 0.9)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    canvas.drawCircle(const Offset(14, 13.9), 7.7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant NumberPinPainter oldDelegate) => oldDelegate.color != color;
}
