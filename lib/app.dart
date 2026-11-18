import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/app_update.dart';
import 'core/geo_gate.dart';
import 'core/session.dart';
import 'core/ui.dart';
import 'features/auth/login_screen.dart';
import 'features/delivery/delivery_shell.dart';
import 'features/factory/factory_shell.dart';
import 'features/seller/seller_shell.dart';

class AkiFoodsApp extends StatelessWidget {
  final Session session;
  final ApiClient api;
  const AkiFoodsApp({super.key, required this.session, required this.api});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AKI Foods',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('mn'),
      supportedLocales: const [Locale('mn'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.isLoaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final user = session.user;
          if (!session.isSignedIn || user == null) return LoginScreen(api: api, session: session);
          // Key нь хэрэглэгчээр — өөр хүн нэвтрэхэд өмнөхийн төлөв үлдэхгүй.
          return UpdateNotice(
            child: switch (user.role) {
              'factory' => FactoryShell(key: ValueKey(user.id), api: api, session: session),
              // ⚠ Борлуулагч/түгээгч GPS зөвшөөрөл өгтөл системийг ашиглахгүй (geo-gate).
              //   Ахлах борлуулагч (senior) борлуулагчийн UI-г хэрэглэнэ, гэхдээ онлайнаар
              //   ажилладаг тул web-тэй адил GPS хаалт, tracking аль аль нь ХЭРЭГГҮЙ.
              'senior' => SellerShell(key: ValueKey(user.id), api: api, session: session),
              'seller' => GeoGate(
                key: ValueKey(user.id),
                api: api,
                child: SellerShell(api: api, session: session),
              ),
              'delivery' => GeoGate(
                key: ValueKey(user.id),
                api: api,
                child: DeliveryShell(api: api, session: session),
              ),
              _ => _WebOnlyScreen(session: session, role: user.role),
            },
          );
        },
      ),
    );
  }
}

// Админ (болон танигдаагүй дүр) апп ашиглахгүй — зөвхөн web хувилбар.
class _WebOnlyScreen extends StatelessWidget {
  final Session session;
  final String role;
  const _WebOnlyScreen({required this.session, required this.role});

  @override
  Widget build(BuildContext context) {
    final label = role == 'admin' ? 'Админ' : role;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.desktop_windows_outlined, size: 48, color: AppColors.muted),
                const SizedBox(height: 12),
                Text(
                  '$label апп ашиглахгүй',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Web хувилбараар нэвтэрнэ үү.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                OutlinedButton(onPressed: session.clear, child: const Text('Системээс гарах')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
