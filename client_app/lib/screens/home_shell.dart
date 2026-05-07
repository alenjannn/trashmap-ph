import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:client_app/screens/map_screen.dart';
import 'package:client_app/screens/report_screen.dart';
import 'package:client_app/screens/schedule_screen.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.roleBadgeLabel,
    super.key,
    this.onSignOut,
  });

  final String roleBadgeLabel;
  final VoidCallback? onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 2; // Default to Schedule
  bool _isPinDropMode = false;
  LatLng? _selectedReportPoint;
  final List<RouteNotificationItem> _routeNotifications = [];
  RealtimeChannel? _notifsChannel;

  @override
  void initState() {
    super.initState();
    _initNotificationsListener();
  }

  @override
  void dispose() {
    if (_notifsChannel != null) {
      SupabaseService.client.removeChannel(_notifsChannel!);
    }
    super.dispose();
  }

  void _initNotificationsListener() {
    _notifsChannel = SupabaseService.client
        .channel('public:route_notifications_log')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'route_notifications_log',
          callback: (payload) async {
            final data = payload.newRecord;
            final String? zoneId = data['zone_id'];
            if (zoneId == null) return;

            // Fetch zone coordinates
            final zoneRes = await SupabaseService.client
                .from('zones')
                .select('lat, lng')
                .eq('id', zoneId)
                .single();

            final double zoneLat = (zoneRes['lat'] as num).toDouble();
            final double zoneLng = (zoneRes['lng'] as num).toDouble();

            // Get current location
            final pos = await _getCurrentLocation();
            if (pos == null) return;

            // Haversine check (500m)
            final distance = _calculateDistance(pos.latitude, pos.longitude, zoneLat, zoneLng);
            if (distance <= 500) {
              if (!mounted) return;
              setState(() {
                _routeNotifications.add(RouteNotificationItem(
                  title: data['title'] ?? 'Route Update',
                  body: data['body'] ?? 'A collection truck is nearby.',
                ));
              });
            }
          },
        )
        .subscribe();
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (_) {
      return null;
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000;
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: false,
      // We keep the Stack body for the floating header/notifications
      body: Stack(
        children: [
          // 1. Main Content (IndexedStack for persistence)
          IndexedStack(
            index: _selectedIndex,
            children: [
              MapScreen(
                selectedPoint: _selectedReportPoint,
                isPinDropMode: _isPinDropMode,
                onPinSelected: (LatLng point) {
                  setState(() {
                    _selectedReportPoint = point;
                    _isPinDropMode = false; // pin placed — drop mode off
                    _selectedIndex = 1;    // return to Report tab
                  });
                },
              ),
              ReportScreen(
                selectedPoint: _selectedReportPoint,
                onRequestPinTab: () {
                  setState(() {
                    _isPinDropMode = true;
                    _selectedIndex = 0;
                  });
                },
              ),
              const ScheduleScreen(),
            ],
          ),

          // 2a. Header Background Gradient (IgnorePointer to allow tapping through to content)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: MediaQuery.of(context).padding.top + 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFFF9FBF9).withOpacity(0.98),
                      const Color(0xFFF9FBF9).withOpacity(0.9),
                      const Color(0xFFF9FBF9).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2b. Interactive Header Content
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'TrashMap PH',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1B4332),
                              letterSpacing: -1.5,
                              shadows: [
                                Shadow(color: Colors.white, blurRadius: 10),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: const Color(0xFF1B4332),
                            ),
                            child: Text(
                              widget.roleBadgeLabel.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onSignOut != null)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
                          ],
                        ),
                        child: IconButton(
                          onPressed: widget.onSignOut,
                          icon: const Icon(Icons.logout_rounded, size: 24),
                          color: const Color(0xFF1B4332),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          // 3. Floating Notifications
          if (_routeNotifications.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 110,
              left: 20,
              right: 20,
              child: Column(
                children: _routeNotifications.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B4332).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF1B4332).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: Color(0xFF74C69D), size: 26),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                              Text(item.body, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _routeNotifications.remove(item)),
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),

      // 4. Liquid Glass Navigation Bar (Moved higher and wrapped in SafeArea)
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), // Increased bottom padding to move it up
          child: ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 100, 
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10)),
                  ],
                ),
                child: NavigationBar(
                  backgroundColor: Colors.transparent, 
                  elevation: 0,
                  height: 100, 
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                      if (index != 0) _isPinDropMode = false;
                    });
                  },
                  destinations: const <NavigationDestination>[
                    NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore_rounded),
                      label: 'Explore',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.add_circle_outline_rounded),
                      selectedIcon: Icon(Icons.add_circle_rounded),
                      label: 'Report',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month_rounded),
                      label: 'Schedule',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RouteNotificationItem {
  RouteNotificationItem({required this.title, required this.body});
  final String title;
  final String body;
}
