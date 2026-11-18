import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Апп бүхэлдээ БОСОО байрлалд зориулагдсан — web-тэй ижил.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('mn');

  final session = Session();
  final api = ApiClient(session);
  session.load();
  runApp(AkiFoodsApp(session: session, api: api));
}
