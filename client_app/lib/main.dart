import 'package:flutter/material.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('TrashMap PH — Client App')),
      ),
    );
  }
}
