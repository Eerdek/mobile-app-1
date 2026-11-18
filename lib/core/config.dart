// Аппын тохиргоо. Backend хаягийг build үед өөрчилж болно:
//   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
// (Android эмулятороос компьютерийн localhost нь 10.0.2.2.)
//
// ⚠ Анхдагч нь PRODUCTION — web-ийн runtime-config.js-тэй ижил хаяг.
//   Туршилтын өгөгдөл production дээр бичигдэхээс болгоомжил.
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://akifoodsbackend.fly.dev/api/v1',
  );

  static const Duration requestTimeout = Duration(seconds: 30);

  /// Шинэ хувилбарын манифест (APK-тай хамт R2-д, tool/publish_apk.js).
  static const String updateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://pub-df56b494764e47fab8edde88d4e6a40f.r2.dev/app/version.json',
  );
}
