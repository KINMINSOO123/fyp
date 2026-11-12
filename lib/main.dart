import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'core/theme/bakery_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );
  if (AppConfig.firebaseConfigured) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
    } catch (_) {
      // In-app notifications and ordinary business features still work.
    }
  }
  runApp(const SmartBakeryApp());
}

class SmartBakeryApp extends StatelessWidget {
  const SmartBakeryApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Bakery',
      debugShowCheckedModeBanner: false,
      theme: BakeryTheme.light,
      home: home ?? const AuthGate(),
    );
  }
}
