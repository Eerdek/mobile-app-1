import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

// Апп Play Store-оор биш, web-ээс APK-аар тардаг тул шинэ хувилбарыг ӨӨРӨӨ
// мэдэгдэнэ. R2 дээрх app/version.json (APK-тай ХАМТ tool/publish_apk.js
// байршуулна):
//   {"build": 2, "version": "1.0.1", "minBuild": 1, "notes": "...",
//    "apk": {"arm64": "<url>", "armv7": "<url>"}}
// ⚠ build < minBuild бол ЗААВАЛ шинэчилнэ (хаах товчгүй) — серверийн
//   эвдрэлтэй өөрчлөлтийн үед хуучин апп-ыг зогсооход хэрэглэнэ.

class AppUpdate {
  final int build;
  final String version;
  final String notes;
  final bool required;
  final Uri apk;
  const AppUpdate({
    required this.build,
    required this.version,
    required this.notes,
    required this.required,
    required this.apk,
  });
}

/// Манифестийг одоогийн build-тэй харьцуулна. Шинэ хувилбаргүй, эсвэл
/// манифест буруу бол null (алдаа шидэхгүй).
AppUpdate? parseUpdate(Object? json, int currentBuild, {bool arm64 = true}) {
  if (json is! Map) return null;
  final build = json['build'];
  final apk = json['apk'];
  if (build is! int || build <= currentBuild || apk is! Map) return null;
  final url = (arm64 ? apk['arm64'] : apk['armv7']) ?? apk['arm64'];
  final uri = url is String ? Uri.tryParse(url) : null;
  if (uri == null || !uri.hasScheme) return null;
  final minBuild = json['minBuild'];
  return AppUpdate(
    build: build,
    version: '${json['version'] ?? build}',
    notes: '${json['notes'] ?? ''}'.trim(),
    required: minBuild is int && currentBuild < minBuild,
    apk: uri,
  );
}

/// ⚠ --split-per-abi нь versionCode-д ABI×1000 нэмдэг (arm64: 2002, armv7: 1002)
///   — pubspec-ийн «+N» дугаартай харьцуулахын тулд хасна (N < 1000).
int buildFromVersionCode(String versionCode) => (int.tryParse(versionCode) ?? 0) % 1000;

Future<AppUpdate?> checkForUpdate() async {
  if (!Platform.isAndroid) return null; // iOS нь APK биш — өөр сувгаар
  try {
    final info = await PackageInfo.fromPlatform();
    final current = buildFromVersionCode(info.buildNumber);
    final res = await http
        .get(Uri.parse(AppConfig.updateManifestUrl), headers: {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    // 32-бит утсанд 64-бит APK суухгүй — тохирох файлыг нээнэ.
    return parseUpdate(jsonDecode(utf8.decode(res.bodyBytes)), current, arm64: Abi.current() != Abi.androidArm);
  } catch (_) {
    return null; // сүлжээгүй үед ажлыг саатуулахгүй
  }
}

/// Нэвтэрсэн хэрэглэгчийн хуудсыг ороож, шинэ хувилбар байвал цонх гаргана.
/// Апп нээгдэхэд ба буцаж ороход (6 цагт нэгээс олонгүй) шалгана.
class UpdateNotice extends StatefulWidget {
  final Widget child;
  const UpdateNotice({super.key, required this.child});

  @override
  State<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<UpdateNotice> with WidgetsBindingObserver {
  static const _interval = Duration(hours: 6);
  DateTime? _checkedAt;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final last = _checkedAt;
    if (_showing || (last != null && DateTime.now().difference(last) < _interval)) return;
    _checkedAt = DateTime.now();
    final update = await checkForUpdate();
    if (update == null || !mounted) return;
    _showing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.required,
      builder: (dialogContext) => PopScope(
        canPop: !update.required,
        child: AlertDialog(
          title: Text('Шинэ хувилбар ${update.version}'),
          content: Text(
            [
              if (update.required) 'Энэ хувилбарыг заавал суулгана — хуучин апп цаашид ажиллахгүй.',
              if (update.notes.isNotEmpty) update.notes,
              'Татсан файлаа нээгээд «Шинэчлэх»-ийг дарна. Өгөгдөл тань хэвээр үлдэнэ.',
            ].join('\n\n'),
          ),
          actions: [
            if (!update.required)
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Дараа')),
            FilledButton(
              onPressed: () => launchUrl(update.apk, mode: LaunchMode.externalApplication),
              child: const Text('Татах'),
            ),
          ],
        ),
      ),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
