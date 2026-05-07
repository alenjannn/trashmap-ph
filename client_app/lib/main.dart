import 'package:flutter/material.dart';
import 'package:client_app/screens/auth_gate.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/theme/app_theme.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await SupabaseService.initialize();
  runApp(const TrashMapApp());
}

class TrashMapApp extends StatelessWidget {
  const TrashMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrashMap PH',
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}
          