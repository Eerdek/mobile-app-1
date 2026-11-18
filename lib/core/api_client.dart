import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'config.dart';
import 'session.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final Object? details;

  const ApiException(this.message, {this.status, this.details});

  @override
  String toString() => message;
}

// Backend-ийн хариу нь `{ ok, data, message }` бүрхүүлтэй — web-ийн
// AppApi.request-тэй ижил: амжилттай бол ЗӨВХӨН `data`-г буцаана.
class ApiClient {
  final Session session;
  final http.Client _http;
  final String baseUrl;

  ApiClient(this.session, {http.Client? client, String? baseUrl})
    : _http = client ?? http.Client(),
      baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  Future<dynamic> get(String path, {Map<String, String?>? query}) => request(path, query: query);

  Future<dynamic> post(String path, Object? body) => request(path, method: 'POST', body: body);

  Future<dynamic> patch(String path, Object? body) => request(path, method: 'PATCH', body: body);

  Future<dynamic> put(String path, Object? body) => request(path, method: 'PUT', body: body);

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String?>? query,
    bool auth = true,
  }) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null) {
      final params = {
        for (final entry in query.entries)
          if (entry.value != null && entry.value!.isNotEmpty) entry.key: entry.value!,
      };
      if (params.isNotEmpty) uri = uri.replace(queryParameters: {...uri.queryParameters, ...params});
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = session.token;
    if (auth && token != null) headers['Authorization'] = 'Bearer $token';

    final http.Response response;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http.send(req).timeout(AppConfig.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('Сервер хариу өгөхгүй байна. Интернэтээ шалгаад дахин оролдоно уу.');
    } on http.ClientException {
      // http 1.x нь SocketException-ийг ч ClientException болгож шиддэг.
      // ⚠ Web дээр (Chrome-оор туршихад) энэ нь ихэвчлэн CORS: production
      //   backend нь localhost-оос ирсэн хүсэлтийг хаадаг. Утсан дээр гарахгүй.
      throw ApiException(
        kIsWeb
            ? 'Сервер энэ хаягаас ирсэн хүсэлтийг хүлээж авсангүй (CORS). Утсан дээр эсвэл local backend-ээр туршина уу.'
            : 'Сүлжээнд холбогдож чадсангүй. Интернэтээ шалгана уу.',
      );
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      payload = decoded is Map<String, dynamic> ? decoded : {'ok': false, 'message': 'Хариу уншихад алдаа гарлаа.'};
    } catch (_) {
      payload = {'ok': false, 'message': 'Хариу уншихад алдаа гарлаа.'};
    }

    // Токен дууссан/хүчингүй (401) — session-г цэвэрлэнэ, апп нэвтрэх дэлгэц
    // рүү өөрөө шилжинэ. Нэвтрэх хүсэлт (auth: false) дээр ХИЙХГҮЙ — буруу
    // нууц үгийн 401 нь session-тэй хамаагүй.
    if (response.statusCode == 401 && auth) {
      await session.clear();
    }

    if (response.statusCode < 200 || response.statusCode >= 300 || payload['ok'] == false) {
      throw ApiException(
        (payload['message'] as String?) ?? 'Алдаа гарлаа.',
        status: response.statusCode,
        details: payload['details'],
      );
    }

    return payload['data'];
  }

  Future<(String token, AppUser user)> login(String identity, String password) async {
    final data = await request(
      '/auth/login',
      method: 'POST',
      body: {'identity': identity, 'password': password},
      auth: false,
    ) as Map<String, dynamic>;
    return (data['token'] as String, AppUser.fromJson(data['user'] as Map<String, dynamic>));
  }
}
