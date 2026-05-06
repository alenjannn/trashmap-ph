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
  bool _routeActionLoading = false;
  bool _mapFullscreen = false;
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
      final String? userId = SupabaseService.client.auth.currentUser?.id;

      // No auth = no route to load.
      if (userId == null || userId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _route = null;
          _stops = <DriverRouteStop>[];
          _loading = false;
        });
        return;
      }

      final dynamic assignmentResponse = await SupabaseService.client
          .from('route_assignments')
          .select('route_id, driver_id, is_active, assigned_at')
          .eq('driver_id', userId)
          .eq('is_active', true)
          .order('assigned_at', ascending: false)
          .limit(1);
      final List<dynamic> assignmentRows = assignmentResponse as List<dynamic>;
      final String? assignedRouteId =
          assignmentRows.isEmpty ? null : assignmentRows.first['route_id'] as String?;

      // No active assignment = nothing to show. Skip route query entirely.
      if (assignedRouteId == null || assignedRouteId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _route = null;
          _stops = <DriverRouteStop>[];
          _loading = false;
        });
        return;
      }

      final routesResponse = await SupabaseService.client
          .from('routes')
          .select('id, truck_id, zone_id, polyline, status')
          .eq('route_date', today)
          .eq('id', assignedRouteId)
          .inFilter('status', <String>['draft', 'published', 'scheduled', 'in_progress', 'completed', 'completed_with_issues'])
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
      final String? zoneId = routeRow['zone_id'] as String?;

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
          truckId: truckId,
          zoneId: zoneId,
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
      final String nowIso = DateTime.now().toIso8601String();
      final dynamic existingProgress = await SupabaseService.client
          .from('route_progress')
          .select('id')
          .eq('route_id', _route!.id)
          .eq('stop_id', stop.id)
          .limit(1);
      if ((existingProgress as List<dynamic>).isNotEmpty) {
        await SupabaseService.client
            .from('route_progress')
            .update(<String, dynamic>{
              'status': 'completed',
              'confirmed_at': nowIso,
              'updated_at': nowIso,
              'driver_id': userId,
            })
            .eq('route_id', _route!.id)
            .eq('stop_id', stop.id);
      } else {
        await SupabaseService.client.from('route_progress').insert(<String, dynamic>{
          'route_id': _route!.id,
          'stop_id': stop.id,
          'truck_id': _route!.truckId,
          'status': 'completed',
          'confirmed_at': nowIso,
          'updated_at': nowIso,
          'driver_id': userId,
        });
      }

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

  Future<void> _startRoute() async {
    if (_route == null || _routeActionLoading) return;
    if (_route!.status == 'in_progress') return;
    if (_route!.status == 'completed' || _route!.status == 'completed_with_issues' || _route!.status == 'cancelled') {
      setState(() {
        _error = 'Cannot start closed route.';
      });
      return;
    }
    setState(() {
      _routeActionLoading = true;
      _error = null;
    });
    try {
      final String? userId = SupabaseService.client.auth.currentUser?.id;
      await SupabaseService.client.from('routes').update(<String, dynamic>{'status': 'in_progress'}).eq('id', _route!.id);
      await SupabaseService.client
          .from('trucks')
          .update(<String, dynamic>{'status': 'en_route'})
          .eq('id', _route!.truckId);
      await SupabaseService.client.from('route_audit_logs').insert(<String, dynamic>{
        'route_id': _route!.id,
        'event_type': 'route_started',
        'actor_user_id': userId,
        'actor_role': 'driver',
        'zone_id': _route!.zoneId,
        'area_label': 'driver_start_route',
        'metadata_json': <String, dynamic>{'source': 'driver_app'},
      });
      final dynamic existingStartNotification = await SupabaseService.client
          .from('route_notifications_log')
          .select('id')
          .eq('route_id', _route!.id)
          .eq('event_type', 'route_started')
          .eq('target_scope', 'both')
          .limit(1);
      if ((existingStartNotification as List<dynamic>).isEmpty) {
        await SupabaseService.client.from('route_notifications_log').insert(<String, dynamic>{
          'route_id': _route!.id,
          'zone_id': _route!.zoneId,
          'event_type': 'route_started',
          'target_scope': 'both',
          'title': 'Collection Started',
          'body': 'Collection in your area has started.',
          'metadata_json': <String, dynamic>{'source': 'driver_app'},
        });
      }
      if (!mounted) return;
      setState(() {
        _route = _route!.copyWith(status: 'in_progress');
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route started.')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Start route failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _routeActionLoading = false;
        });
      }
    }
  }

  Future<void> _endRoute() async {
    if (_route == null || _routeActionLoading) return;
    if (_route!.status == 'completed' || _route!.status == 'completed_with_issues') return;
    if (_route!.status == 'cancelled') {
      setState(() {
        _error = 'Cannot end cancelled route.';
      });
      return;
    }
    setState(() {
      _routeActionLoading = true;
      _error = null;
    });
    try {
      final String? userId = SupabaseService.client.auth.currentUser?.id;
      final int unresolved = _stops.where((DriverRouteStop stop) => stop.status == 'pending' || stop.status == 'arrived').length;
      final String finalStatus = unresolved > 0 ? 'completed_with_issues' : 'completed';
      await SupabaseService.client.from('routes').update(<String, dynamic>{'status': finalStatus}).eq('id', _route!.id);
      await SupabaseService.client.from('trucks').update(<String, dynamic>{'status': 'idle'}).eq('id', _route!.truckId);
      await SupabaseService.client.from('route_audit_logs').insert(<String, dynamic>{
        'route_id': _route!.id,
        'event_type': 'route_completed',
        'actor_user_id': userId,
        'actor_role': 'driver',
        'zone_id': _route!.zoneId,
        'area_label': 'driver_end_route',
        'metadata_json': <String, dynamic>{'unresolved': unresolved, 'status': finalStatus},
      });
      final dynamic existingCompleteNotification = await SupabaseService.client
          .from('route_notifications_log')
          .select('id')
          .eq('route_id', _route!.id)
          .eq('event_type', 'route_completed')
          .eq('target_scope', 'both')
          .limit(1);
      if ((existingCompleteNotification as List<dynamic>).isEmpty) {
        await SupabaseService.client.from('route_notifications_log').insert(<String, dynamic>{
          'route_id': _route!.id,
          'zone_id': _route!.zoneId,
          'event_type': 'route_completed',
          'target_scope': 'both',
          'title': 'Collection Completed',
          'body': unresolved > 0
              ? 'Collection in your area ended with unresolved stops.'
              : 'Collection in your area is now completed.',
          'metadata_json': <String, dynamic>{'unresolved': unresolved, 'status': finalStatus},
        });
      }
      if (!mounted) return;
      setState(() {
        _route = _route!.copyWith(status: finalStatus);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route ended.')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'End route failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _routeActionLoading = false;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (route == null)
                        const Text('No assigned route today. Check back soon or ask your admin.')
                      else ...<Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                route.truckLabel,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: route.status == 'in_progress'
                                    ? const Color(0xFF2563EB)
                                    : route.status == 'completed' || route.status == 'completed_with_issues'
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFF6B7280),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                route.status.toUpperCase().replaceAll('_', ' '),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_routeActionLoading)
                          const Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                        else
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: route.status == 'in_progress' ||
                                          route.status == 'completed' ||
                                          route.status == 'completed_with_issues' ||
                                          route.status == 'cancelled'
                                      ? null
                                      : _startRoute,
                                  child: const Text('Start Route'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: route.status != 'in_progress' && route.status != 'published'
                                      ? null
                                      : _endRoute,
                                  child: const Text('End Route'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
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
                  title: 'Route Map',
                  subtitle: route?.status == 'in_progress' ? 'ROUTE IN PROGRESS — Follow the blue path.' : 'Polyline route with ordered stops.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        height: _mapFullscreen
                            ? 480
                            : (route?.status == 'in_progress' ? 360 : 260),
                        child: route == null
                            ? const Center(child: Text('No route assigned yet.'))
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: route.points.isNotEmpty
                                        ? route.points[route.points.length ~/ 2]
                                        : const LatLng(14.676, 121.0437),
                                    initialZoom: route.status == 'in_progress' ? 15 : 14,
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
                                            strokeWidth: 5.0,
                                            // Blue — matches admin dashboard route color
                                            color: const Color(0xFF2563EB),
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
                                                stop.status == 'completed'
                                                    ? Icons.check_circle
                                                    : stop.status == 'skipped'
                                                        ? Icons.cancel
                                                        : Icons.location_on,
                                                color: stop.status == 'completed'
                                                    ? const Color(0xFF16A34A)
                                                    : stop.status == 'skipped'
                                                        ? const Color(0xFFEF4444)
                                                        : const Color(0xFF14B8A6),
                                                size: 32,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (route != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() { _mapFullscreen = !_mapFullscreen; }),
                            icon: Icon(_mapFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 18),
                            label: Text(_mapFullscreen ? 'Collapse' : 'Expand Map', style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
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
    required this.truckId,
    required this.zoneId,
    required this.truckLabel,
    required this.status,
    required this.points,
  });

  final String id;
  final String truckId;
  final String? zoneId;
  final String truckLabel;
  final String status;
  final List<LatLng> points;

  DriverRouteHeader copyWith({String? status}) {
    return DriverRouteHeader(
      id: id,
      truckId: truckId,
      zoneId: zoneId,
      truckLabel: truckLabel,
      status: status ?? this.status,
      points: points,
    );
  }
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
