// lib/main.dart
//
// ENTRY POINT: Initializes the Behavioral Vault (Hive) and wires the
// SoulprintEngine into the widget tree via Provider before the first frame.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/soulprint_engine.dart';
import 'screens/payment_screen.dart';
import 'services/risk_context_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await Hive.initFlutter();
  await Hive.openBox<List>('soulprint_profile');

  // Init risk context service (opens its own Hive boxes)
  final riskService = RiskContextService();
  await riskService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SoulprintEngine()..start(),
        ),
        ChangeNotifierProvider.value(value: riskService),
      ],
      child: const VigilUpiApp(),
    ),
  );
}

class VigilUpiApp extends StatelessWidget {
  const VigilUpiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VigilUPI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const PaymentScreen(),
    );
  }
}
