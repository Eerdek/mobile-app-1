import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_printer.dart';
import 'escpos.dart';

class _RasterJob {
  final Uint8List rgba;
  final int width;
  final int height;
  const _RasterJob(this.rgba, this.width, this.height);
}

Uint8List _rasterize(_RasterJob job) => rgbaToEscPos(job.rgba, job.width, job.height);

/// [boundaryKey]-тэй RepaintBoundary-г 576 цэгийн зураг болгоод ESC/POS байт
/// болгоно. Хөрвүүлэлт нь тусдаа isolate-д (урт хуудсанд UI гацахгүй).
Future<Uint8List> captureReceipt(GlobalKey boundaryKey) async {
  final context = boundaryKey.currentContext;
  final boundary = context?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw const PrinterException('Хэвлэх хуудас олдсонгүй.');
  }
  final ratio = dotsPerLine / boundary.size.width;
  final image = await boundary.toImage(pixelRatio: ratio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw const PrinterException('Хуудсыг зураг болгоход алдаа гарлаа.');
    return await compute(_rasterize, _RasterJob(data.buffer.asUint8List(), image.width, image.height));
  } finally {
    image.dispose();
  }
}

/// Принтер сонгох жагсаалт — web дээрх Chrome-ийн цонхны оронд.
Future<String?> showPrinterPicker(BuildContext context, Stream<List<BleDevice>> devices) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Принтер сонгох', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Принтерээ асаагаад ойртуулна уу. Нэг принтер хоёр нэрээр харагдвал HB66… эсвэл Printer… гэснийг сонгоно.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: StreamBuilder<List<BleDevice>>(
                stream: devices,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${snapshot.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    );
                  }
                  final list = snapshot.data ?? const [];
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Принтер хайж байна…'),
                        ],
                      ),
                    );
                  }
                  final sorted = [...list]..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in sorted)
                        ListTile(
                          leading: const Icon(Icons.print_outlined),
                          title: Text(d.name?.isNotEmpty == true ? d.name! : d.deviceId),
                          subtitle: Text(d.rssi == null ? d.deviceId : '${d.deviceId} · ${d.rssi} dBm'),
                          onTap: () {
                            BlePrinter.instance.rememberName(d.name ?? d.deviceId);
                            Navigator.of(sheetContext).pop(d.deviceId);
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// «Хэвлэх» товч — нэг товчоор: холбох → зураг болгох → илгээх, явцыг
/// товчин дээр харуулна. Утсан дээр системийн хэвлэлт рүү УНАХГҮЙ (энэ
/// термо принтер PDF ойлгодоггүй, үсэгний шуурга хэвлэдэг).
class PrintButton extends StatefulWidget {
  final GlobalKey boundaryKey;
  final bool enabled;
  const PrintButton({super.key, required this.boundaryKey, this.enabled = true});

  @override
  State<PrintButton> createState() => _PrintButtonState();
}

class _PrintButtonState extends State<PrintButton> {
  String? _status;
  bool _busy = false;

  Future<void> _print() async {
    setState(() {
      _busy = true;
      _status = 'Бэлдэж байна…';
    });
    try {
      final bytes = await captureReceipt(widget.boundaryKey);
      if (!mounted) return;
      setState(() => _status = 'Принтер холбож байна…');
      await BlePrinter.instance.printBytes(
        bytes,
        picker: (devices) => showPrinterPicker(context, devices),
        onProgress: (ratio) {
          if (!mounted) return;
          setState(() => _status = 'Хэвлэж байна… ${(ratio * 100).round().clamp(0, 99)}%');
        },
      );
      if (!mounted) return;
      // Принтер датаг авсны дараа дотоод буфераа хэвлэж гүйцээдэг.
      setState(() => _status = 'Хэвлэж байна…');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() => _status = 'Хэвлэгдлээ ✓');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    } on PrinterCancelled {
      // Хэрэглэгч сонголтоо цуцалсан — юу ч хэлэхгүй.
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Хэвлэх'),
          content: Text(
            'Bluetooth-ээр хэвлэж чадсангүй ($error). Принтерээ асаалттай, ойрхон эсэхийг шалгаад дахин дарна уу.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await BlePrinter.instance.forgetPrinter();
              },
              child: const Text('Өөр принтер'),
            ),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Ойлголоо')),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: widget.enabled && !_busy ? _print : null,
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.print_outlined, size: 18),
      label: Text(_status ?? 'Хэвлэх'),
    );
  }
}
