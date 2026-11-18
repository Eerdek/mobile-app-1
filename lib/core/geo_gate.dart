import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'geo.dart';
import 'ui.dart';

/// Байршлын ХАТУУ хаалт — борлуулагч/түгээгч GPS зөвшөөрөл өгтөл системийг
/// ашиглахгүй (web-ийн geo-gate.js). Хаах товчгүй: зорилго нь албадах.
/// Зөвшөөрөл олгогдмогц GPS track эхэлнэ; тохиргооноос буцааж таславал
/// апп руу эргэж ирэхэд (resume) хаалт дахин гарна.
class GeoGate extends StatefulWidget {
  final ApiClient api;
  final Widget child;
  const GeoGate({super.key, required this.api, required this.child});

  @override
  State<GeoGate> createState() => _GeoGateState();
}

class _GeoGateState extends State<GeoGate> with WidgetsBindingObserver {
  GeoAccess? _access;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GeoService.instance.stopTracking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Тохиргооноос буцаж ирэхэд дахин шалгана.
    if (state == AppLifecycleState.resumed) _evaluate();
  }

  Future<void> _evaluate() async {
    final access = await GeoService.instance.checkAccess();
    if (!mounted) return;
    _apply(access);
  }

  void _apply(GeoAccess access) {
    final wasGranted = _access == GeoAccess.granted;
    setState(() => _access = access);
    if (access == GeoAccess.granted && !wasGranted) {
      GeoService.instance.startTracking(widget.api);
    } else if (access != GeoAccess.granted && wasGranted) {
      GeoService.instance.stopTracking();
    }
  }

  Future<void> _request() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final access = _access;
      if (access == GeoAccess.serviceOff) {
        await Geolocator.openLocationSettings();
      } else if (access == GeoAccess.deniedForever) {
        // Native prompt дахин гарахгүй — тохиргоо руу заавал.
        await Geolocator.openAppSettings();
      } else {
        _apply(await GeoService.instance.requestAccess());
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == GeoAccess.granted) return widget.child;
    if (access == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final (message, help, button) = switch (access) {
      GeoAccess.serviceOff => (
          'Утасны байршил (GPS) унтраалттай байна.',
          'Тохиргоо → Байршил (Location)-ыг асаагаад апп руу буцаж орно уу.',
          'Байршил асаах',
        ),
      GeoAccess.deniedForever => (
          'Байршлын зөвшөөрөл хаагдсан байна.',
          'Тохиргоо → Апп → AKI Foods → Зөвшөөрөл → Байршил → «Апп ашиглах үед зөвшөөрөх»-ийг сонгоод буцаж орно уу.',
          'Тохиргоо нээх',
        ),
      _ => (
          'Захиалга авах, GPS байршил илгээхийн тулд байршлын зөвшөөрөл заавал нээлттэй байх ёстой. '
              'Зөвшөөрөхгүй бол системийг ашиглах боломжгүй.',
          null,
          'Байршил зөвшөөрөх',
        ),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(color: Color(0xFFE7F3EE), shape: BoxShape.circle),
                    child: const Icon(Icons.location_on_outlined, size: 38, color: AppColors.brand),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Байршил идэвхжүүлэх шаардлагатай',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
                  if (help != null) ...[
                    const SizedBox(height: 10),
                    Text(help, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _requesting ? null : _request,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.my_location),
                    label: Text(button),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
