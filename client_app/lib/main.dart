import 'package:flutter/material.dart';
import 'package:client_app/screens/home_shell.dart';
import 'package:client_app/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrashMapApp());
}

class TrashMapApp extends StatelessWidget {
  const TrashMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrashMap PH',
      theme: AppTheme.light(),
      home: const HomeShell(),
    );
  }
}
