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

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000; 
    final double phi1 = lat1 * pi / 180;
    final double phi2 = lat2 * pi / 180;
    final double dPhi = (lat2 - lat1) * pi / 180;
    final double dLambda = (lng2 - lng1) * pi / 180;
    final double a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final Position? position = await _resolvePosition();

    try {
      // 1. Fetch all active schedules with their zones
      final dynamic scheduleResponse = await SupabaseService.client
          .from('schedules')
          .select('id, collection_day, time_window_start, time_window_end, zone_id, zones(id, name, lat, lng)')
          .eq('is_active', true);

      final List<Map<String, dynamic>> rawSchedules = List<Map<String, dynamic>>.from(scheduleResponse as List<dynamic>);

      if (position == null) {
        if (!mounted) return;
        setState(() {
          _schedules = [];
          _loading = false;
          _locationStatus = 'Need location to find routes';
        });
        return;
      }

      // 2. Fetch all collection points that are assigned to any of these zones
      final List<String> zoneIds = rawSchedules.map((s) => s['zone_id'].toString()).toSet().toList();
      final dynamic pointsResponse = await SupabaseService.client
          .from('collection_points')
          .select('id, zone_id, lat, lng')
          .eq('is_active', true)
          .inFilter('zone_id', zoneIds);

      final List<Map<String, dynamic>> allPoints = List<Map<String, dynamic>>.from(pointsResponse as List<dynamic>);

      // 3. Filter schedules: Only keep those where at least one collection point in its zone is within 150m
      final List<Map<String, dynamic>> filteredSchedules = rawSchedules.where((schedule) {
        final String sZoneId = schedule['zone_id'].toString();
        final zonePoints = allPoints.where((p) => p['zone_id'].toString() == sZoneId);
        
        return zonePoints.any((p) {
          final double pLat = (p['lat'] as num).toDouble();
          final double pLng = (p['lng'] as num).toDouble();
          return _distanceMeters(position.latitude, position.longitude, pLat, pLng) <= _radiusMeters;
        });
      }).toList();

      filteredSchedules.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final String dayA = (a['collection_day'] ?? '').toString().toLowerCase();
        final String dayB = (b['collection_day'] ?? '').toString().toLowerCase();
        return (_dayOrder[dayA] ?? 99).compareTo(_dayOrder[dayB] ?? 99);
      });

      if (!mounted) return;
      setState(() {
        _schedules = filteredSchedules;
        _position = position;
        _loading = false;
        _locationStatus = _schedules.isEmpty ? 'No collection points within 300m' : 'Found nearby collection points';
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

  String _formatTime(dynamic raw) {
    final String t = (raw ?? '').toString();
    if (t.isEmpty) return '--:--';
    final List<String> parts = t.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : t;
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
            final String dayRaw = (row['collection_day'] ?? '').toString();
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
                          '${_formatTime(row['time_window_start'])} – ${_formatTime(row['time_window_end'])}',
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
