import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/widgets/section_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  DriverRouteHeader? _route;
  List<DriverRouteStop> _stops = <DriverRouteStop>[];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDriverRoute();
  }

  Future<void> _loadDriverRoute() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final String today = DateTime.now().toIso8601String().substring(0, 10);
      final routesResponse = await SupabaseService.client
          .from('routes')
          .select('id, truck_id, polyline, status')
          .eq('route_date', today)
          .eq('source', 'ai_optimized')
          .inFilter('status', <String>['published', 'in_progress', 'completed'])
          .order('created_at', ascending: false)
          .limit(1);

      final List<dynamic> routeRows = routesResponse as List<dynamic>;
      if (routeRows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _route = null;
          _stops = <DriverRouteStop>[];
          _loading = false;
        });
        return;
      }

      final dynamic routeRow = routeRows.first;
      final String routeId = routeRow['id'] as String;
      final String polyline = (routeRow['polyline'] as String?) ?? '';
      final String status = (routeRow['status'] as String?) ?? 'published';
      final String truckId = routeRow['truck_id'] as String;

      final truckResponse = await SupabaseService.client
          .from('trucks')
          .select('truck_code, driver_name')
          .eq('id', truckId)
          .maybeSingle();

      final String truckCode = (truckResponse?['truck_code'] as String?) ?? 'TRUCK';
      final String driverName = (truckResponse?['driver_name'] as String?) ?? 'Unassigned';

      final stopsResponse = await SupabaseService.client
          .from('route_stops')
          .select('id, stop_order, label, lat, lng, status')
          .eq('route_id', routeId)
          .order('stop_order', ascending: true);

      final List<dynamic> stopRows = stopsResponse as List<dynamic>;
      final List<DriverRouteStop> loadedStops = stopRows.map((dynamic row) {
        return DriverRouteStop(
          id: row['id'] as String,
          order: row['stop_order'] as int,
          label: (row['label'] as String?) ?? 'Stop',
          point: LatLng((row['lat'] as num).toDouble(), (row['lng'] as num).toDouble()),
          status: (row['status'] as String?) ?? 'pending',
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _route = DriverRouteHeader(
          id: routeId,
          truckLabel: '$truckCode • $driverName',
          status: status,
          points: _parsePolyline(polyline),
        );
        _stops = loadedStops;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load assigned route: $error';
        _loading = false;
      });
    }
  }

  List<LatLng> _parsePolyline(String polyline) {
    if (polyline.trim().isEmpty) return <LatLng>[];
    return polyline
        .split(';')
        .map((String segment) => segment.trim())
        .where((String segment) => segment.isNotEmpty)
        .map((String segment) {
          final List<String> parts = segment.split(',');
          if (parts.length != 2) return null;
          final double? lat = double.tryParse(parts[0]);
          final double? lng = double.tryParse(parts[1]);
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  Future<void> _confirmPickup(DriverRouteStop stop) async {
    if (_route == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final String? userId = SupabaseService.client.auth.currentUser?.id;
      await SupabaseService.client
          .from('route_progress')
          .update(<String, dynamic>{
            'status': 'completed',
            'confirmed_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            'driver_id': userId,
          })
          .eq('route_id', _route!.id)
          .eq('stop_id', stop.id);

      await SupabaseService.client
          .from('route_stops')
          .update(<String, dynamic>{
            'status': 'completed',
          })
          .eq('id', stop.id);

      if (!mounted) return;
      setState(() {
        _stops = _stops.map((DriverRouteStop item) {
          if (item.id != stop.id) return item;
          return item.copyWith(status: 'completed');
        }).toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pickup confirmed for stop #${stop.order}.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Confirm pickup failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DriverRouteHeader? route = _route;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TrashMap PH Driver'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _loadDriverRoute,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh route',
          ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SectionCard(
                  title: 'Driver Console',
                  subtitle: 'Role active and listening for route assignment.',
                  child: Text(
                    route == null
                        ? 'No assigned route for today yet.'
                        : 'Assigned: ${route.truckLabel} (${route.status.toUpperCase()})',
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Notice',
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Today Route Map',
                  subtitle: 'Polyline route with ordered stops.',
                  child: SizedBox(
                    height: 280,
                    child: route == null
                        ? const Center(child: Text('No route polyline yet.'))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: route.points.isNotEmpty ? route.points.first : const LatLng(14.676, 121.0437),
                                initialZoom: 14,
                              ),
                              children: <Widget>[
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.trashmapph.client_app',
                                ),
                                if (route.points.length >= 2)
                                  PolylineLayer(
                                    polylines: <Polyline>[
                                      Polyline(
                                        points: route.points,
                                        strokeWidth: 4.0,
                                        color: const Color(0xFF10B981),
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: _stops
                                      .map(
                                        (DriverRouteStop stop) => Marker(
                                          point: stop.point,
                                          width: 40,
                                          height: 40,
                                          child: Icon(
                                            stop.status == 'completed' ? Icons.check_circle : Icons.location_on,
                                            color: stop.status == 'completed' ? const Color(0xFF16A34A) : const Color(0xFF1D4ED8),
                                            size: 30,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Stop List',
                  subtitle: 'Confirm pickup to update LGU tracker.',
                  child: route == null || _stops.isEmpty
                      ? const Text('No stops assigned yet.')
                      : Column(
                          children: _stops.map((DriverRouteStop stop) {
                            final bool completed = stop.status == 'completed';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                                color: completed ? const Color(0xFFF0FDF4) : Colors.white,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          '#${stop.order} ${stop.label}',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${stop.point.latitude.toStringAsFixed(6)}, ${stop.point.longitude.toStringAsFixed(6)}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: completed || _submitting ? null : () => _confirmPickup(stop),
                                    child: Text(completed ? 'Confirmed' : 'Confirm Pickup'),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }
}

class DriverRouteHeader {
  DriverRouteHeader({
    required this.id,
    required this.truckLabel,
    required this.status,
    required this.points,
  });

  final String id;
  final String truckLabel;
  final String status;
  final List<LatLng> points;
}

class DriverRouteStop {
  DriverRouteStop({
    required this.id,
    required this.order,
    required this.label,
    required this.point,
    required this.status,
  });

  final String id;
  final int order;
  final String label;
  final LatLng point;
  final String status;

  DriverRouteStop copyWith({String? status}) {
    return DriverRouteStop(
      id: id,
      order: order,
      label: label,
      point: point,
      status: status ?? this.status,
    );
  }
}
