import 'package:flutter/material.dart';
import 'package:client_app/screens/directory_screen.dart';
import 'package:client_app/screens/map_screen.dart';
import 'package:client_app/screens/report_screen.dart';
import 'package:client_app/screens/schedule_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const List<Widget> _tabs = <Widget>[
    MapScreen(),
    ReportScreen(),
    ScheduleScreen(),
    DirectoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrashMap PH'),
        centerTitle: false,
      ),
      body: _tabs[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.report_gmailerrorred_outlined),
            selectedIcon: Icon(Icons.report),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Directory',
          ),
        ],
      ),
    );
  }
}
