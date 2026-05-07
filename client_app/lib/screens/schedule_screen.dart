import 'dart:math';
import 'package:flutter/material.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/widgets/section_card.dart';
import 'package:geolocator/geolocator.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  // 300m diameter = 150m radius
  static const double _radiusMeters = 150.0;

  static const Map<String, int> _dayOrder = <String, int>{
    'monday': 1,
    'tuesday': 2,
    'wednesday': 3,
    'thursday': 4,
    'friday': 5,
    'saturday': 6,
    'sunday': 7,
  };

  bool _loading = true;
  String? _error;
  String? _locationStatus; 
  List<Map<String, dynamic>> _schedules = <Map<String, dynamic>>[];
  Position? _position;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<Position?> _resolvePosition() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationStatus = 'GPS Disabled';
        return null;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        _locationStatus = 'Permission Denied';
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
    } catch (_) {
      _locationStatus = 'Location unavailable';
      return null;
    }
  }

  // Calculate Haversine distance in meters
  // Re-implementing correctly with math.
  double _calcDist(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final Position? position = await _resolvePosition();

    try {
      // Fetch weekly_routes joined with assigned collection points (route_template_stops → collection_points)
      // and zone label. Filter happens client-side: user must be within 150m radius (300m diameter)
      // of at least one collection point ASSIGNED to that weekly route.
      final dynamic routeResponse = await SupabaseService.client
          .from('weekly_routes')
          .select(
            'id, name, recurrence_day, start_hour, end_hour, zone_id, '
            'zones(id, name), '
            'route_template_stops(collection_points(id, lat, lng, is_active))',
          )
          .eq('is_active', true);

      final List<Map<String, dynamic>> rawRoutes =
          List<Map<String, dynamic>>.from(routeResponse as List<dynamic>);

      if (position == null) {
        if (!mounted) return;
        setState(() {
          _schedules = [];
          _loading = false;
          _locationStatus = 'Need location to find routes';
        });
        return;
      }

      // Filter: only keep weekly_routes that have at least one assigned collection point
      // within _radiusMeters of the citizen's current GPS fix.
      final List<Map<String, dynamic>> filteredRoutes = rawRoutes.where((route) {
        final dynamic stops = route['route_template_stops'];
        if (stops is! List) return false;
        for (final dynamic stop in stops) {
          final dynamic cp = stop is Map<String, dynamic> ? stop['collection_points'] : null;
          if (cp is! Map<String, dynamic>) continue;
          if (cp['is_active'] == false) continue;
          final num? lat = cp['lat'] as num?;
          final num? lng = cp['lng'] as num?;
          if (lat == null || lng == null) continue;
          if (_calcDist(position.latitude, position.longitude, lat.toDouble(), lng.toDouble()) <=
              _radiusMeters) {
            return true;
          }
        }
        return false;
      }).toList();

      filteredRoutes.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final String dayA = (a['recurrence_day'] ?? '').toString().toLowerCase();
        final String dayB = (b['recurrence_day'] ?? '').toString().toLowerCase();
        final int cmp = (_dayOrder[dayA] ?? 99).compareTo(_dayOrder[dayB] ?? 99);
        if (cmp != 0) return cmp;
        final int hA = (a['start_hour'] as num?)?.toInt() ?? 0;
        final int hB = (b['start_hour'] as num?)?.toInt() ?? 0;
        return hA.compareTo(hB);
      });

      if (!mounted) return;
      setState(() {
        _schedules = filteredRoutes;
        _position = position;
        _loading = false;
        _locationStatus = _schedules.isEmpty
            ? 'No collection points within 300m'
            : 'Found nearby collection points';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Load failed: $error';
        _loading = false;
      });
    }
  }

  String _dayLabel(String raw) => raw.isEmpty ? 'Unknown' : '${raw[0].toUpperCase()}${raw.substring(1)}';

  bool _isToday(String rawDay) {
    const List<String> weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    return rawDay.toLowerCase() == weekdays[DateTime.now().weekday - 1];
  }

  String _formatHour(dynamic raw) {
    final int h = (raw is num) ? raw.toInt() : int.tryParse((raw ?? '').toString()) ?? 0;
    final int hh = h.clamp(0, 24);
    return '${hh.toString().padLeft(2, '0')}:00';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      displacement: 120,
      color: const Color(0xFF1B4332),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 100, 20, 140),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _position != null ? Icons.location_on_rounded : Icons.location_off_rounded,
                        size: 14,
                        color: _position != null ? const Color(0xFF40916C) : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _locationStatus ?? 'Detecting...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _position != null ? const Color(0xFF40916C) : const Color(0xFF94A3B8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_error != null)
            SectionCard(
              title: 'Error',
              icon: Icons.error_outline_rounded,
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13)),
            ),

          if (_schedules.isEmpty && _error == null)
            SectionCard(
              title: 'No Routes',
              subtitle: '300m Diameter Scan',
              icon: Icons.not_listed_location_rounded,
              child: const Text(
                'No collection points found within 300m of your location. Make sure you are at a designated pickup spot.',
                style: TextStyle(height: 1.6, color: Color(0xFF64748B), fontSize: 13),
              ),
            ),

          ..._schedules.map((Map<String, dynamic> row) {
            final dynamic zone = row['zones'];
            final String zoneName = zone is Map<String, dynamic> ? (zone['name']?.toString() ?? 'Zone') : 'Zone';
            final String dayRaw = (row['recurrence_day'] ?? '').toString();
            final bool today = _isToday(dayRaw);

            return SectionCard(
              title: zoneName,
              subtitle: _dayLabel(dayRaw),
              icon: Icons.local_shipping_rounded,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: today ? const Color(0xFFD8F3DC).withOpacity(0.3) : const Color(0xFFF1F5F9).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: today ? const Color(0xFF1B4332) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_formatHour(row['start_hour'])} – ${_formatHour(row['end_hour'])}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: today ? const Color(0xFF1B4332) : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    if (today)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B4332),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'TODAY',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
