import 'package:akifoods_app/core/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const manifest = {
    'build': 3,
    'version': '1.0.2',
    'minBuild': 2,
    'notes': 'Алдаа зассан',
    'apk': {'arm64': 'https://x.dev/app/akifoods-arm64.apk', 'armv7': 'https://x.dev/app/akifoods-armv7.apk'},
  };

  test('шинэ build байвал шинэчлэл буцаана', () {
    final u = parseUpdate(manifest, 2)!;
    expect(u.version, '1.0.2');
    expect(u.required, isFalse);
    expect(u.apk.toString(), endsWith('arm64.apk'));
  });

  test('ижил эсвэл шинэ build дээр null', () {
    expect(parseUpdate(manifest, 3), isNull);
    expect(parseUpdate(manifest, 4), isNull);
  });

  test('minBuild-ээс доош бол заавал', () {
    expect(parseUpdate(manifest, 1)!.required, isTrue);
  });

  test('32-бит утсанд armv7 APK', () {
    expect(parseUpdate(manifest, 1, arm64: false)!.apk.toString(), endsWith('armv7.apk'));
  });

  test('split-per-abi versionCode-оос build дугаар', () {
    expect(buildFromVersionCode('2002'), 2);
    expect(buildFromVersionCode('1002'), 2);
    expect(buildFromVersionCode('2'), 2);
    expect(buildFromVersionCode(''), 0);
  });

  test('эвдэрсэн манифест алдаа шидэхгүй', () {
    expect(parseUpdate(null, 1), isNull);
    expect(parseUpdate({'build': '3'}, 1), isNull);
    expect(parseUpdate({'build': 3, 'apk': {'arm64': 'not a url'}}, 1), isNull);
  });
}
