import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppUser {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final String status;
  final String? zone;
  final bool mustChangePassword;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    required this.status,
    this.email,
    this.phone,
    this.zone,
    this.mustChangePassword = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: '${json['id']}',
    fullName: (json['fullName'] ?? '') as String,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    role: (json['role'] ?? '') as String,
    status: (json['status'] ?? '') as String,
    zone: json['zone'] as String?,
    mustChangePassword: json['mustChangePassword'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'role': role,
    'status': status,
    'zone': zone,
    'mustChangePassword': mustChangePassword,
  };

  // Header/drawer дээрх нэр — web-ийн displayName-тэй ижил дараалал.
  String get displayName {
    for (final value in [fullName, email, phone]) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return 'Хэрэглэгч';
  }

  String get initial {
    final name = displayName;
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }
}

// Нэвтрэлтийн төлөв. Token нь утасны найдвартай сан (Keychain / Keystore)-д
// хадгалагдана — web шиг localStorage-д биш.
class Session extends ChangeNotifier {
  static const _tokenKey = 'zs_token';
  static const _userKey = 'zs_user';

  final FlutterSecureStorage _storage;

  Session([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  String? _token;
  AppUser? _user;
  bool _loaded = false;

  String? get token => _token;
  AppUser? get user => _user;
  bool get isLoaded => _loaded;
  bool get isSignedIn => _token != null && _user != null;

  Future<void> load() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      final raw = await _storage.read(key: _userKey);
      _user = raw == null ? null : AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Эвдэрсэн/уншигдахгүй сан — дахин нэвтрүүлнэ.
      _token = null;
      _user = null;
    }
    if (_token == null || _user == null) {
      _token = null;
      _user = null;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(String token, AppUser user) async {
    _token = token;
    _user = user;
    notifyListeners();
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  Future<void> clear() async {
    if (_token == null && _user == null) return;
    _token = null;
    _user = null;
    notifyListeners();
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
