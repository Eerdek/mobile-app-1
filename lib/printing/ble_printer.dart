// BLE термо принтер (ESC/POS). web-ийн bt-print.js-ийн холболт/илгээлтийн
// логикийг native BLE рүү шилжүүлсэн. Гол ялгаа: web дээр Chrome-ийн
// requestDevice цонх байсан бол энд апп өөрөө скан хийж жагсаалт харуулна.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import 'escpos.dart';

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);
  @override
  String toString() => message;
}

// Тэргүүлэх дараалал — web-тэй ИЖИЛ. Олдсон дарааллаар биш, ЭНЭ дарааллаар
// шалгана (Android дээр сервисийн дараалал платформ бүрд өөр ирдэг).
const List<String> printerServices = [
  '000018f0-0000-1000-8000-00805f9b34fb',
  '49535343-fe7d-4ae5-8fa9-9fafd205e455', // ISSC/Microchip transparent UART
  'e7810a71-73ae-499d-8c15-faa9aef0c3f2', // түгээмэл хятад ESC/POS модуль
  '0000ff00-0000-1000-8000-00805f9b34fb',
  '0000ffe0-0000-1000-8000-00805f9b34fb',
];

// Принтер маягийн нэрс. ⚠ «HB» — энэ принтерийн ЖИНХЭНЭ (принтер сервистэй)
// BLE тал нь "HB66…" нэрээр зарладаг.
const List<String> printerNamePrefixes = ['80', '58', 'POS', 'Printer', 'PT-', 'MTP', 'BT', 'HB'];

// Богино ("18f0") ба бүтэн UUID-г нэг хэлбэрт оруулна.
String _canonical(String uuid) {
  try {
    return BleUuidParser.string(uuid).toLowerCase();
  } catch (_) {
    return uuid.toLowerCase();
  }
}

const List<int> _chunkLadder = [244, 180, 120, 60, 20];
const String _deviceKey = 'zs_bt_printer_id';
const String _deviceNameKey = 'zs_bt_printer_name';

/// Скан хийж байх үед апп хэрэглэгчид принтер сонгуулах callback.
/// Буцаах утга: сонгосон deviceId, эсвэл цуцалбал null.
typedef DevicePicker = Future<String?> Function(Stream<List<BleDevice>> devices);

class BlePrinter {
  BlePrinter._();
  static final BlePrinter instance = BlePrinter._();

  String? _deviceId;
  String? _service;
  String? _characteristic;
  bool _canWrite = false;
  bool _canWriteWithoutResponse = false;
  int _chunkSize = 20;
  StreamSubscription<bool>? _connSub;

  String channelLabel = '';

  bool get isConnected => _characteristic != null;

  Future<String?> savedPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceNameKey);
  }

  Future<void> forgetPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceKey);
    await prefs.remove(_deviceNameKey);
    await _disconnect();
  }

  Future<void> _ensureBluetoothOn() async {
    await UniversalBle.requestPermissions();
    final state = await UniversalBle.getBluetoothAvailabilityState();
    switch (state) {
      case AvailabilityState.poweredOn:
        return;
      case AvailabilityState.poweredOff:
        throw const PrinterException('Bluetooth унтраалттай байна. Асаагаад дахин оролдоно уу.');
      case AvailabilityState.unauthorized:
        throw const PrinterException('Bluetooth ашиглах зөвшөөрөл өгөөгүй байна. Тохиргооноос зөвшөөрнө үү.');
      case AvailabilityState.unsupported:
        throw const PrinterException('Энэ төхөөрөмж Bluetooth LE дэмжихгүй.');
      default:
        // unknown/resetting — богино хүлээгээд дахин шалгана.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (await UniversalBle.getBluetoothAvailabilityState() != AvailabilityState.poweredOn) {
          throw const PrinterException('Bluetooth бэлэн биш байна. Түр хүлээгээд дахин оролдоно уу.');
        }
    }
  }

  // Скан: принтер маягийн төхөөрөмжүүдийг л жагсаана ("Unknown device" хогийн оронд).
  Stream<List<BleDevice>> _scan() {
    final found = <String, BleDevice>{};
    late StreamController<List<BleDevice>> controller;
    StreamSubscription<BleDevice>? sub;
    controller = StreamController<List<BleDevice>>(
      onListen: () async {
        sub = UniversalBle.scanStream.listen((device) {
          final name = device.name ?? '';
          final looksLikePrinter =
              printerNamePrefixes.any(name.startsWith) ||
              device.services.any((s) => printerServices.contains(_canonical(s)));
          if (!looksLikePrinter) return;
          found[device.deviceId] = device;
          controller.add(found.values.toList());
        });
        try {
          await UniversalBle.startScan();
        } catch (e) {
          controller.addError(PrinterException('Скан эхлүүлж чадсангүй: $e'));
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await UniversalBle.stopScan();
        } catch (_) {}
      },
    );
    return controller.stream;
  }

  Future<void> ensureConnected(DevicePicker picker) async {
    if (_characteristic != null && _deviceId != null) return;
    await _ensureBluetoothOn();

    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceKey);
    var freshlyPicked = false;
    if (deviceId == null) {
      deviceId = await picker(_scan());
      if (deviceId == null) throw const PrinterCancelled();
      freshlyPicked = true;
    }

    try {
      await _connect(deviceId, freshlyPicked: freshlyPicked);
    } on PrinterException {
      rethrow;
    } catch (e) {
      // Хадгалсан принтер олдохгүй/холбогдохгүй бол сонголтыг мартаж,
      // дараагийн оролдлогод жагсаалт дахин гарна.
      if (!freshlyPicked) await prefs.remove(_deviceKey);
      throw PrinterException('Принтерт холбогдож чадсангүй. Асаалттай, ойрхон эсэхийг шалгана уу. ($e)');
    }
    await prefs.setString(_deviceKey, deviceId);
  }

  Future<void> _connect(String deviceId, {required bool freshlyPicked}) async {
    await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 15));
    _deviceId = deviceId;
    await _connSub?.cancel();
    _connSub = UniversalBle.connectionStream(deviceId).listen((connected) {
      if (!connected) {
        debugPrint('[bt] холболт тасарлаа');
        _characteristic = null;
      }
    });

    final services = await UniversalBle.discoverServices(deviceId);
    final ordered = <BleService>[];
    for (final uuid in printerServices) {
      for (final s in services) {
        if (_canonical(s.uuid) == uuid) ordered.add(s);
      }
    }

    for (final service in ordered) {
      BleCharacteristic? fast;
      BleCharacteristic? reliable;
      BleCharacteristic? notify;
      for (final c in service.characteristics) {
        if (fast == null && c.properties.contains(CharacteristicProperty.writeWithoutResponse)) fast = c;
        if (reliable == null && c.properties.contains(CharacteristicProperty.write)) reliable = c;
        if (notify == null && c.properties.contains(CharacteristicProperty.notify)) notify = c;
      }
      final chosen = fast ?? reliable;
      if (chosen == null) continue;

      _service = service.uuid;
      _characteristic = chosen.uuid;
      _canWriteWithoutResponse = chosen.properties.contains(CharacteristicProperty.writeWithoutResponse);
      _canWrite = chosen.properties.contains(CharacteristicProperty.write);

      // Багцын хэмжээ. Native Android нь MTU-г зөв хэлэлцдэг — гэхдээ web дээр
      // 180Б Android-д хамгийн цэвэр гарсан тул түүнээс дээш гаргахгүй.
      var chunk = _canWriteWithoutResponse ? 180 : 20;
      try {
        final mtu = await UniversalBle.requestMtu(deviceId, 247);
        chunk = mtu - 3 < chunk ? mtu - 3 : chunk;
      } catch (_) {
        chunk = 20;
      }
      _chunkSize = chunk < 20 ? 20 : chunk;

      // Тогтворжуулах ёслол: notify-д бүртгүүлж GATT/шифрлэлтийн тохиролцоог
      // гүйцээлгэнэ. Шинэ pair-ийн дараах эхний бичилтүүд эвдэрдэг нь web
      // дээр туршилтаар батлагдсан — 1.5с / 0.3с хүлээнэ.
      if (notify != null) {
        try {
          await UniversalBle.subscribeNotifications(deviceId, service.uuid, notify.uuid);
        } catch (_) {}
      }
      await Future<void>.delayed(Duration(milliseconds: freshlyPicked ? 1500 : 300));
      channelLabel = '${service.uuid.substring(4, 8)}·${_canWriteWithoutResponse ? 'WWoR' : 'wr'}·$_chunkSize';
      debugPrint('[bt] суваг: $channelLabel');
      return;
    }

    // Принтерийн сервис алга — буруу «дүр» (ерөнхий сервистэй тал) сонгогдсон.
    final found = services.map((s) => s.uuid.length >= 8 ? s.uuid.substring(4, 8) : s.uuid).join(',');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceKey);
    await _disconnect();
    throw PrinterException(
      'Энэ төхөөрөмж принтерийн суваггүй (олдсон: ${found.isEmpty ? 'хоосон' : found}). '
      'Дахин дараад жагсаалтаас ӨӨР нэрийг (ж: HB66… эсвэл Printer…) сонгоно уу.',
    );
  }

  Future<void> _disconnect() async {
    final id = _deviceId;
    _characteristic = null;
    _service = null;
    _deviceId = null;
    await _connSub?.cancel();
    _connSub = null;
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
  }

  Future<void> rememberName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceNameKey, name);
  }

  Future<void> _write(Uint8List chunk, {required bool withResponse}) {
    return UniversalBle.write(
      _deviceId!,
      _service!,
      _characteristic!,
      chunk,
      withoutResponse: !withResponse && _canWriteWithoutResponse,
    );
  }

  Future<void> _sendBytes(Uint8List bytes, void Function(double)? onProgress) async {
    if (_characteristic == null) throw const PrinterException('Принтер холбогдоогүй байна.');
    final canSync = _canWrite && _canWriteWithoutResponse;

    // Золиосны эхлэл: 32 NUL байт — холболт тогтсоны дараах эхний багцууд
    // гээгдвэл NUL-ууд л алдагдана (ESC/POS парсер NUL-ийг алгасдаг).
    await _write(Uint8List(20), withResponse: false);
    await _write(Uint8List(12), withResponse: false);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final rate = sendRateFor(bytes.length);
    final watch = Stopwatch()..start();
    var sinceSync = 0;
    var offset = 0;
    while (offset < bytes.length) {
      final end = offset + _chunkSize > bytes.length ? bytes.length : offset + _chunkSize;
      final chunk = Uint8List.sublistView(bytes, offset, end);
      try {
        // 2КБ тутам нэг багцыг хариутай бичилтээр — backpressure.
        if (canSync && sinceSync >= 2048) {
          await _write(chunk, withResponse: true);
          sinceSync = 0;
        } else {
          await _write(chunk, withResponse: false);
        }
      } catch (error) {
        final step = _chunkLadder.indexOf(_chunkSize);
        if (step >= 0 && step < _chunkLadder.length - 1) {
          _chunkSize = _chunkLadder[step + 1];
          debugPrint('[bt] багц багасгав → $_chunkSize ($offset байт дээр)');
          continue;
        }
        if (_chunkSize > 20 && step < 0) {
          _chunkSize = 20;
          continue;
        }
        rethrow;
      }
      offset += chunk.length;
      sinceSync += chunk.length;
      // Хурд хязгаарлагч — принтерийн буферээс түрүүлэхгүй.
      final allowed = sendBurst + watch.elapsedMilliseconds / 1000 * rate;
      if (offset > allowed) {
        await Future<void>.delayed(Duration(milliseconds: ((offset - allowed) / rate * 1000).ceil()));
      }
      onProgress?.call(offset / bytes.length);
    }
    if (_canWrite) {
      await _write(Uint8List.fromList(const [0x1b, 0x64, 0x02]), withResponse: true); // ESC d 2
    }
  }

  /// Бүтэн урсгал: холбогдоно → илгээнэ. Дундаа тасарвал НЭГ удаа дахин
  /// холбогдож бүтнээр нь дахин илгээнэ — дутуу баримт үлдээхгүй.
  Future<void> printBytes(Uint8List bytes, {required DevicePicker picker, void Function(double)? onProgress}) async {
    await ensureConnected(picker);
    try {
      await _sendBytes(bytes, onProgress);
    } catch (first) {
      if (first is PrinterCancelled) rethrow;
      debugPrint('[bt] эхний оролдлого унав: $first — дахин холбогдоно');
      _characteristic = null;
      onProgress?.call(0);
      final id = _deviceId;
      if (id != null) {
        try {
          await UniversalBle.disconnect(id);
        } catch (_) {}
      }
      _deviceId = null;
      await ensureConnected(picker);
      await _sendBytes(bytes, onProgress);
    }
  }
}

class PrinterCancelled extends PrinterException {
  const PrinterCancelled() : super('Цуцлагдлаа');
}
