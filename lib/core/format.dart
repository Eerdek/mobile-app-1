import 'dart:math' as math;

import 'package:intl/intl.dart';

// ── Тоо ─────────────────────────────────────────────────────────────────────
final NumberFormat _intFormat = NumberFormat('#,##0', 'mn');

// Бүхэл тоо (ширхэг) — web-ийн formatQty (toLocaleString("mn-MN")).
String formatQty(num? value) => _intFormat.format((value ?? 0).round());

// Бүхэл тоог бүхлээр, бутархайг 3 орон хүртэл (хоосон тэгүүдгүй) — web-ийн
// үлдэгдлийн fmtQty. Түүхий эд кг/литрээр бутархай байдаг.
String formatAmount(num? value) {
  final n = ((value ?? 0) * 1000).round() / 1000;
  if (n == n.roundToDouble()) return _intFormat.format(n.round());
  return n.toString();
}

num toNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

int toInt(Object? value) => toNum(value).truncate();

// ── Огноо ───────────────────────────────────────────────────────────────────
String _pad(int n) => n.toString().padLeft(2, '0');

DateTime? parseDate(Object? iso) {
  if (iso is! String || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

// ⚠ Өдрийн түлхүүрийг ЛОКАЛ огноогоор гаргана, ISO мөрийг огтолж БИШ:
//   createdAt нь UTC тул орой үүссэн захиалгын ISO огноо МАРГААШИЙНХ болно.
String dayKeyOf(Object? iso) {
  final d = parseDate(iso);
  if (d == null) return 'none';
  return '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
}

String ymd(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

class OrderDay {
  final String label;
  final bool old;
  const OrderDay(this.label, this.old);
}

// Захиалгын өдрийн шошго: өнөөдөр → "Өнөөдөр", өчигдөр → "Өчигдөр",
// бусад → "08.10". `old` нь өмнөх өдрийнх (эхэлж гаргах) эсэх.
OrderDay? orderDay(Object? iso, {DateTime? now}) {
  final date = parseDate(iso);
  if (date == null) return null;
  final today = now ?? DateTime.now();
  final startToday = DateTime(today.year, today.month, today.day);
  final startDate = DateTime(date.year, date.month, date.day);
  // ⚠ inDays биш, календарийн өдрөөр — DST-гүй ч цагийн бүсийн зөрүүнээс хамгаална.
  final days = ((startToday.millisecondsSinceEpoch - startDate.millisecondsSinceEpoch) / 86400000).round();
  if (days == 0) return const OrderDay('Өнөөдөр', false);
  if (days == 1) return const OrderDay('Өчигдөр', true);
  return OrderDay('${_pad(date.month)}.${_pad(date.day)}', days > 0);
}

String dayLabelOf(Object? iso) => orderDay(iso)?.label ?? 'Огноогүй';

// Хэвлэлтийн цаг — "2026/10/24 09:05".
String stamp([DateTime? at]) {
  final d = at ?? DateTime.now();
  return '${d.year}/${_pad(d.month)}/${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
}

// Хөдөлгөөний түүхийн цаг — "10.24 09:05".
String shortDateTime(Object? iso) {
  final d = parseDate(iso);
  if (d == null) return '';
  return '${_pad(d.month)}.${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
}

// ── Монгол цагаан толгойн эрэмбэ ─────────────────────────────────────────────
// Dart-д Intl.Collator байхгүй. Юникодын дараалалд Ө (U+04E9), Ү (U+04AF),
// Ё (U+0451) нь Я-гийн АРД ордог тул энгийн compareTo нь «Өрөм»-ийг «Ян»-ы
// ард тавина. Энд web-ийн Intl.Collator("mn", {sensitivity:"base",
// numeric:true})-тэй ойролцоо дүрэм:
//   • том/жижиг үсэг ялгахгүй
//   • тоон хэсгийг ТООГООР харьцуулна ("Бүс 2" < "Бүс 10")
//   • зай/тэмдэгт < тоо < латин < кирилл
const String _mnAlphabet = 'абвгдеёжзийклмноөпрстуүфхцчшщъыьэюя';

final Map<int, int> _mnWeight = {for (var i = 0; i < _mnAlphabet.length; i++) _mnAlphabet.codeUnitAt(i): 2000 + i};

int _charWeight(int code) {
  final lower = String.fromCharCode(code).toLowerCase().codeUnitAt(0);
  final mn = _mnWeight[lower];
  if (mn != null) return mn;
  if (lower >= 0x61 && lower <= 0x7a) return 1000 + (lower - 0x61);
  if (lower < 0x80) return lower; // зай, цэг таслал
  return 3000 + lower;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

int mnCompare(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      var ei = i;
      while (ei < a.length && _isDigit(a.codeUnitAt(ei))) {
        ei++;
      }
      var ej = j;
      while (ej < b.length && _isDigit(b.codeUnitAt(ej))) {
        ej++;
      }
      final na = BigInt.parse(a.substring(i, ei));
      final nb = BigInt.parse(b.substring(j, ej));
      final cmp = na.compareTo(nb);
      if (cmp != 0) return cmp;
      i = ei;
      j = ej;
      continue;
    }
    final wa = _isDigit(ca) ? 500 : _charWeight(ca);
    final wb = _isDigit(cb) ? 500 : _charWeight(cb);
    if (wa != wb) return wa - wb;
    i++;
    j++;
  }
  return (a.length - i) - (b.length - j);
}

// ── Ангиллын эрэмбэ ──────────────────────────────────────────────────────────
// ⚠ АНГИЛЛААР ЭРЭМБЭЛЭХ ГАНЦ ДҮРЭМ — баримт, түгээгчийн жагсаалт, захиалга засах,
//   үйлдвэрийн самбар бүгд үүнийг дуудна. Ангилалгүй бараа ҮРГЭЛЖ доор.
int compareByCategory(String? catA, String nameA, String? catB, String nameB) {
  final ea = (catA ?? '').trim().isEmpty;
  final eb = (catB ?? '').trim().isEmpty;
  if (ea != eb) return ea ? 1 : -1;
  final byCat = mnCompare((catA ?? '').trim(), (catB ?? '').trim());
  if (byCat != 0) return byCat;
  return mnCompare(nameA, nameB);
}

/// JSON мөрүүдийг ({name, categoryName}) ангиллаар эрэмбэлсэн ХУУЛБАР.
List<Map<String, dynamic>> sortItemsByCategory(Iterable<Map<String, dynamic>> items) => items.toList()
  ..sort((a, b) => compareByCategory(
        a['categoryName'] as String?,
        '${a['name'] ?? ''}',
        b['categoryName'] as String?,
        '${b['name'] ?? ''}',
      ));

// ── Мөнгө ────────────────────────────────────────────────────────────────────
String formatMoney(num? value) => '${_intFormat.format((value ?? 0).round())}₮';

final NumberFormat _decFormat = NumberFormat('#,##0.00', 'mn');

/// НӨАТ гэх мэт бутархай дүн — "1,234.55₮".
String moneyDecimal(num? value) => '${_decFormat.format(value ?? 0)}₮';

/// "2026-10-24 09:05" — web-ийн formatDate (гараар, locale-оос хамааралгүй).
String formatDateTime(Object? iso) {
  final d = iso is DateTime ? iso : parseDate(iso);
  if (d == null) return '-';
  return '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
}

/// Баримтын огноо — "2026/10/24".
String receiptDate(Object? iso) {
  final d = parseDate(iso);
  if (d == null) return '-';
  return '${d.year}/${_pad(d.month)}/${_pad(d.day)}';
}

String hhmm(Object? iso) {
  final d = parseDate(iso);
  return d == null ? '-' : '${_pad(d.hour)}:${_pad(d.minute)}';
}

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// ── Зай ─────────────────────────────────────────────────────────────────────
/// Хоёр цэгийн ойролцоо зай (метр) — Haversine.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Цэг полигон дотор эсэх (ray casting). polygon = [[lat, lng], ...].
bool pointInPolygon(double lat, double lng, List<List<double>> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final latI = polygon[i][0], lngI = polygon[i][1];
    final latJ = polygon[j][0], lngJ = polygon[j][1];
    final crosses = (latI > lat) != (latJ > lat) && lng < (lngJ - lngI) * (lat - latI) / (latJ - latI) + lngI;
    if (crosses) inside = !inside;
  }
  return inside;
}
