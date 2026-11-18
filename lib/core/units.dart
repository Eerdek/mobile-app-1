// Нэгж харуулах — ШИРХЭГ ба БАГЦЫГ ЯЛГААТАЙ харуулах ГАНЦ эх сурвалж
// (web-ийн units.js). Тус бүрд нь гараар бичвэл зөрж, борлуулагч «48»-ыг
// 48 багц гэж уншиж 1 152 ширхэг захиалж магадгүй.
import 'format.dart';

const String unitPiece = 'ш';
const String unitPieceWord = 'ширхэг';
const String unitPack = 'багц';

Object? _pick(Map<String, dynamic> item, String a, String b) => item[a] ?? item[b];

/// Багцгүй гэж тооцох: null / 0 / 1 / хог. ⚠ backend-ийн normalizePackSize-тай ижил.
int? packSizeOf(Map<String, dynamic> item) {
  final raw = _pick(item, 'packSize', 'pack_size');
  if (raw == null) return null;
  final size = toNum(raw).truncate();
  return size > 1 ? size : null;
}

bool isPack(Map<String, dynamic> item) =>
    _pick(item, 'unitKind', 'unit_kind') == 'pack' && packSizeOf(item) != null;

/// Захиалсан нэгжийн тоо (багцын тоо эсвэл ширхэг).
num orderedQtyOf(Map<String, dynamic> item) {
  final ordered = _pick(item, 'orderedQty', 'ordered_qty');
  if (ordered != null && num.tryParse('$ordered') != null) return toNum(ordered);
  final packSize = packSizeOf(item);
  final qty = toNum(_pick(item, 'qty', 'quantity'));
  return packSize != null && isPack(item) ? qty / packSize : qty;
}

/// Физик ширхэг — үйлдвэр үүнийг бэлддэг.
num piecesOf(Map<String, dynamic> item) {
  final qty = _pick(item, 'qty', 'quantity');
  if (qty != null && num.tryParse('$qty') != null) return toNum(qty);
  return orderedQtyOf(item) * (packSizeOf(item) ?? 1);
}

String _fmt(num v) => formatAmount(v);

/// "5 ш" эсвэл "2 багц (48 ш)".
String formatUnits(Map<String, dynamic> item) {
  final pieces = piecesOf(item);
  if (!isPack(item)) return '${_fmt(pieces)} $unitPiece';
  return '${_fmt(orderedQtyOf(item))} $unitPack (${_fmt(pieces)} $unitPiece)';
}

/// 72мм роль цаасанд БОГИНО: "5ш" эсвэл "2бг×24 = 48ш".
String formatUnitsShort(Map<String, dynamic> item) {
  final pieces = piecesOf(item);
  if (!isPack(item)) return '${_fmt(pieces)}$unitPiece';
  return '${_fmt(orderedQtyOf(item))}бг×${packSizeOf(item)} = ${_fmt(pieces)}$unitPiece';
}

/// Каталогт «1 багц = 24 ш».
String packLabel(Object? packSize) {
  final size = toNum(packSize).truncate();
  return size > 1 ? '1 $unitPack = ${_fmt(size)} $unitPiece' : '';
}
