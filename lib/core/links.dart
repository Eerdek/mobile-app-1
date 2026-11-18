import 'package:url_launcher/url_launcher.dart';

/// Утас руу залгах.
Future<bool> callPhone(String? phone) async {
  final cleaned = (phone ?? '').replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return false;
  return launchUrl(Uri(scheme: 'tel', path: cleaned));
}

final RegExp _latLng = RegExp(r'^-?\d+(\.\d+)?,-?\d+(\.\d+)?$');

/// Дэлгүүрийн GPS ("lat,lng") эсвэл хаягаар Google Maps ЧИГЛҮҮЛЭХ холбоос.
/// GPS байвал хамгийн нарийвчлалтай (web-ийн buildDirectionsUrl).
Uri? directionsUri(String? location, String? address) {
  final loc = (location ?? '').trim().replaceAll(RegExp(r'\s+'), '');
  if (_latLng.hasMatch(loc)) {
    return Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(loc)}');
  }
  final addr = (address ?? '').trim();
  return addr.isEmpty ? null : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(addr)}');
}

Future<bool> openDirections(String? location, String? address) async {
  final uri = directionsUri(location, address);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// "lat,lng" → (lat, lng) эсвэл null.
(double, double)? parseLatLng(String? value) {
  final s = (value ?? '').replaceAll(RegExp(r'\s+'), '');
  if (!_latLng.hasMatch(s)) return null;
  final parts = s.split(',');
  return (double.parse(parts[0]), double.parse(parts[1]));
}
