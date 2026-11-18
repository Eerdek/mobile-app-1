// Зураг → ESC/POS raster (GS v 0). web-ийн bt-print.js canvasToEscPos-ийн
// ЯГ хуулбар — тэнд бичигдсэн бүх хэмжилт (80HB6 принтер, realme RMX3630)
// энэ кодод ч хүчинтэй. Тоонуудыг тайлбаргүйгээр бүү өөрчил.
import 'dart:math' as math;
import 'dart:typed_data';

const int dotsPerLine = 576; // 72мм × 8 цэг/мм
const int bytesPerLine = dotsPerLine ~/ 8;

// GS v 0 нэг командын мөрийн тоо. Жижиг band = зарим firmware өндөр band
// дээр гацдаг эрсдэлийг тойрно.
const int maxBandRows = 128;

// Босоо залруулга. Принтер raster мөрийг 203dpi-гийн цэгээс богино зайд
// хэвлэдэг тул USB-ийн хэвлэлттэй ижил урттай болгохын тулд ×1.25 сунгана.
// ⚠ Сунгалтыг ЗУРАГ дээр биш, МӨР ДАВХАРДУУЛЖ хийнэ — бүдгэрэл үүсэхгүй.
const double defaultVScale = 1.25;

// m=0 (хэвийн). 0x02 (давхар өндөр) нь бүх текстийг тодруулдаг байсан —
// bt-print.js-ийн 2026-08-21 тэмдэглэлийг үз.
const int rasterMode = 0x00;

// ⚠⚠ ЦАГААН МӨР АЛГАСАХЫГ БҮҮ ОРОЛД — ESC J / ESC 3+LF хоёулаа 80HB6 дээр
//    мөр давхарлуулсан. Цагаан мөрийг raster дотор нь илгээнэ.

/// [rgba] нь [width]×[height] хэмжээтэй RGBA8888 пиксел (ui.ImageByteFormat.rawRgba).
Uint8List rgbaToEscPos(Uint8List rgba, int width, int height, {double vScale = defaultVScale}) {
  final outHeight = (height * vScale).round();
  final rowBytes = Uint8List(bytesPerLine * outHeight);
  final rowHasInk = Uint8List(outHeight);

  bool isDark(int x, int y) {
    if (y >= height || x >= width) return false;
    final p = (y * width + x) * 4;
    final lum = 0.299 * rgba[p] + 0.587 * rgba[p + 1] + 0.114 * rgba[p + 2];
    return rgba[p + 3] > 64 && lum < 160;
  }

  for (var y = 0; y < outHeight; y++) {
    var ink = 0;
    final rowOffset = y * bytesPerLine;
    final srcRow = (y / vScale).floor();
    for (var xByte = 0; xByte < bytesPerLine; xByte++) {
      var byte = 0;
      for (var bit = 0; bit < 8; bit++) {
        if (isDark(xByte * 8 + bit, srcRow)) byte |= 0x80 >> bit;
      }
      // ⚠ DLE (0x10) нь зарим firmware-д raster ДУНДААС ч «бодит цагийн»
      //   команд болдог. 0x30: зэргэлдээ нэг цэг нэмэгдэнэ (үл мэдэгдэнэ).
      if (byte == 0x10) byte = 0x30;
      rowBytes[rowOffset + xByte] = byte;
      ink |= byte;
    }
    rowHasInk[y] = ink != 0 ? 1 : 0;
  }

  // Төгсгөлийн цагааныг тайрна.
  var lastInk = outHeight - 1;
  while (lastInk >= 0 && rowHasInk[lastInk] == 0) {
    lastInk--;
  }
  final usedHeight = lastInk + 1;

  final out = BytesBuilder(copy: false);
  out.add(const [0x1b, 0x40]); // ESC @ — reset
  for (var top = 0; top < usedHeight; top += maxBandRows) {
    final rows = math.min(maxBandRows, usedHeight - top);
    out.add([0x1d, 0x76, 0x30, rasterMode, bytesPerLine & 0xff, bytesPerLine >> 8, rows & 0xff, rows >> 8]);
    out.add(Uint8List.sublistView(rowBytes, top * bytesPerLine, (top + rows) * bytesPerLine));
  }
  out.add(const [0x1b, 0x64, 0x04]); // төгсгөлд 4 мөр гүйлгэх
  return out.toBytes();
}

// ── Илгээх хурд ─────────────────────────────────────────────────────────────
// Принтерийн дотоод BLE→UART буфер ~11400 Б/с «иддэг» (m=0). Түүнээс хурдан
// илгээвэл урт баримт дундаасаа ASCII хог болно. Хэмжилтийн хүснэгтийг
// bt-print.js-ээс үз.
const int defaultSendRate = 12000;
const int longDocBytes = 160 * 1024;
const int longDocRate = 10000;
const int sendBurst = 2048;

int sendRateFor(int byteCount) => byteCount > longDocBytes ? longDocRate : defaultSendRate;
