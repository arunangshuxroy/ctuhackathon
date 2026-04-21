// lib/main.dart
import 'package:dynamic_color/dynamic_color.dart';
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

  await Hive.initFlutter();
  await Hive.openBox<List>('soulprint_profile');

  final riskService = RiskContextService();
  await riskService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SoulprintEngine()..start()),
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
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'VigilUPI',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: AppTheme.light(lightDynamic),
          darkTheme: AppTheme.dark(darkDynamic),
          home: const PaymentScreen(),
        );
      },
    );
  }
}
