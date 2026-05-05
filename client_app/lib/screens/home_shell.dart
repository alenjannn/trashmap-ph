import 'package:flutter/material.dart';
import 'package:client_app/screens/directory_screen.dart';
import 'package:client_app/screens/map_screen.dart';
import 'package:client_app/screens/report_screen.dart';
import 'package:client_app/screens/schedule_screen.dart';
import 'package:latlong2/latlong.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.onSignOut,
    this.roleBadgeLabel = 'Citizen',
  });

  final VoidCallback? onSignOut;
  final String roleBadgeLabel;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  LatLng? _selectedReportPoint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('TrashMap PH'),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: const Color(0xFFDCFCE7),
              ),
              child: Text(
                widget.roleBadgeLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF166534),
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: <Widget>[
          if (widget.onSignOut != null)
            IconButton(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
            ),
        ],
      ),
      body: <Widget>[
        MapScreen(
          selectedPoint: _selectedReportPoint,
          onPinSelected: (LatLng point) {
            setState(() {
              _selectedReportPoint = point;
            });
          },
        ),
        ReportScreen(
          selectedPoint: _selectedReportPoint,
          onRequestPinTab: () {
            setState(() {
              _selectedIndex = 0;
            });
          },
        ),
        const ScheduleScreen(),
        const DirectoryScreen(),
      ][_selectedIndex],
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
