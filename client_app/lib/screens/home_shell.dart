import 'package:flutter/material.dart';
import 'package:client_app/screens/map_screen.dart';
import 'package:client_app/screens/report_screen.dart';
import 'package:client_app/screens/schedule_screen.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _isPinDropMode = false;
  RealtimeChannel? _notificationsChannel;
  List<RouteNotificationItem> _routeNotifications = <RouteNotificationItem>[];

  @override
  void initState() {
    super.initState();
    _loadRouteNotifications();
    _notificationsChannel = SupabaseService.client
        .channel('mobile-route-notifications-v1')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'route_notifications_log',
          callback: (_) => _loadRouteNotifications(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final RealtimeChannel? channel = _notificationsChannel;
    if (channel != null) {
      SupabaseService.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _loadRouteNotifications() async {
    try {
      final String? userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) return;
      final dynamic zoneResponse = await SupabaseService.client
          .from('citizen_zone_subscriptions')
          .select('zone_id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .limit(100);
      final List<String> zoneIds =
          (zoneResponse as List<dynamic>).map((dynamic row) => row['zone_id'] as String).toList();

      final dynamic notificationsResponse = await SupabaseService.client
          .from('route_notifications_log')
          .select('id, event_type, title, body, target_scope, zone_id, created_at')
          .order('created_at', ascending: false)
          .limit(80);
      final List<dynamic> rows = notificationsResponse as List<dynamic>;
      final List<RouteNotificationItem> items = rows
          .where((dynamic row) {
            final String scope = (row['target_scope'] as String?) ?? '';
            if (scope == 'admin') return false;
            final String? zoneId = row['zone_id'] as String?;
            if (scope == 'both' || scope == 'citizen_zone') {
              if (zoneIds.isEmpty) return false;
              if (zoneId == null) return true;
              return zoneIds.contains(zoneId);
            }
            return false;
          })
          .map((dynamic row) => RouteNotificationItem(
                id: row['id'] as String,
                title: (row['title'] as String?) ?? 'Route notification',
                body: (row['body'] as String?) ?? '',
                eventType: (row['event_type'] as String?) ?? 'event',
                createdAt: (row['created_at'] as String?) ?? '',
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _routeNotifications = items.take(2).toList();
      });
    } catch (_) {
      // keep shell resilient if notification feed unavailable
    }
  }

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
      body: Column(
        children: <Widget>[
          if (_routeNotifications.isNotEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFFECFDF5),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _routeNotifications
                    .map(
                      (RouteNotificationItem item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${item.title}: ${item.body}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: <Widget>[
                MapScreen(
                  selectedPoint: _selectedReportPoint,
                  isPinDropMode: _isPinDropMode,
                  onPinSelected: (LatLng point) {
                    setState(() {
                      _selectedReportPoint = point;
                      _isPinDropMode = false;
                    });
                  },
                ),
                ReportScreen(
                  selectedPoint: _selectedReportPoint,
                  onRequestPinTab: () {
                    setState(() {
                      _selectedIndex = 0;
                      _isPinDropMode = true;
                    });
                  },
                ),
                const ScheduleScreen(),
              ],
            ),
          ),
        ],
      ),
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
        ],
      ),
    );
  }
}

class RouteNotificationItem {
  RouteNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.eventType,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String eventType;
  final String createdAt;
}
