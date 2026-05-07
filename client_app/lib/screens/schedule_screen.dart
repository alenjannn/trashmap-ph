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
  // 1 km diameter = 500 m radius
  static const double _radiusMeters = 500.0;

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
  String? _locationStatus; // shown as subtitle under heading
  List<Map<String, dynamic>> _schedules = <Map<String, dynamic>>[];
  Position? _position;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ─── GPS helpers ──────────────────────────────────────────────────────────

  Future<Position?> _resolvePosition() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationStatus = 'Location services are off — showing all zones.';
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _locationStatus =
            'Location permission denied — showing all zones.';
        return null;
      }

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      _locationStatus =
          'Showing schedules within 1 km of your location.';
      return pos;
    } catch (_) {
      _locationStatus = 'Could not get location — showing all zones.';
      return null;
    }
  }

  // Haversine distance in metres between two lat/lng points.
  double _distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000; // Earth radius in metres
    final double phi1 = lat1 * pi / 180;
    final double phi2 = lat2 * pi / 180;
    final double dPhi = (lat2 - lat1) * pi / 180;
    final double dLambda = (lng2 - lng1) * pi / 180;
    final double a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ─── Data fetch ───────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _locationStatus = null;
    });

    // 1. Get GPS (may be null if permission denied / service off).
    final Position? position = await _resolvePosition();

    // 2. Fetch all active schedules with zone coordinates.
    try {
      final dynamic response = await SupabaseService.client
          .from('schedules')
          .select(
            'id, collection_day, time_window_start, time_window_end, '
            'zones(id, name, lat, lng)',
          )
          .eq('is_active', true)
          .limit(200);

      List<Map<String, dynamic>> rows =
          List<Map<String, dynamic>>.from(response as List<dynamic>);

      // 3. Filter by GPS distance if we have a position.
      if (position != null) {
        rows = rows.where((Map<String, dynamic> row) {
          final dynamic zone = row['zones'];
          if (zone is! Map<String, dynamic>) return false;
          final double? zoneLat = (zone['lat'] as num?)?.toDouble();
          final double? zoneLng = (zone['lng'] as num?)?.toDouble();
          if (zoneLat == null || zoneLng == null) return false;
          final double dist = _distanceMeters(
              position.latitude, position.longitude, zoneLat, zoneLng);
          return dist <= _radiusMeters;
        }).toList();
      }

      // 4. Sort by day of week.
      rows.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final String dayA =
            (a['collection_day'] ?? '').toString().toLowerCase();
        final String dayB =
            (b['collection_day'] ?? '').toString().toLowerCase();
        return (_dayOrder[dayA] ?? 99).compareTo(_dayOrder[dayB] ?? 99);
      });

      if (!mounted) return;
      setState(() {
        _schedules = rows;
        _position = position;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load schedule: $error';
        _loading = false;
      });
    }
  }

  // ─── Formatting helpers ───────────────────────────────────────────────────

  String _dayLabel(String raw) {
    if (raw.isEmpty) return 'Unknown day';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  bool _isToday(String rawDay) {
    const List<String> weekdays = <String>[
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    return rawDay.toLowerCase() == weekdays[DateTime.now().weekday - 1];
  }

  String _formatTime(dynamic raw) {
    final String t = (raw ?? '').toString();
    if (t.isEmpty) return '--:--';
    // Strip seconds if present (e.g. "06:00:00" → "06:00")
    final List<String> parts = t.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return t;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          // ── Heading ────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 6, 4, 4),
            child: Text(
              'Collection Schedule',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),

          // ── Location status subtitle ───────────────────────────────────
          if (_locationStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Row(
                children: <Widget>[
                  Icon(
                    _position != null
                        ? Icons.location_on
                        : Icons.location_off_outlined,
                    size: 14,
                    color: _position != null
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _locationStatus!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _position != null
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Error banner ───────────────────────────────────────────────
          if (_error != null) ...<Widget>[
            SectionCard(
              title: 'Schedule load error',
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB91C1C)),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Empty state ────────────────────────────────────────────────
          if (_schedules.isEmpty && _error == null)
            SectionCard(
              title: _position != null
                  ? 'No schedules near you'
                  : 'No active schedule yet',
              child: Text(
                _position != null
                    ? 'No collection routes are scheduled within 1 km of your current location.'
                    : 'The LGU has not published any collection schedules yet.',
              ),
            ),

          // ── Schedule cards ─────────────────────────────────────────────
          ..._schedules.map((Map<String, dynamic> row) {
            final dynamic zone = row['zones'];
            final String zoneName = zone is Map<String, dynamic>
                ? (zone['name']?.toString() ?? 'Unknown zone')
                : 'Unknown zone';
            final String dayRaw =
                (row['collection_day'] ?? '').toString();
            final bool today = _isToday(dayRaw);
            final String startTime = _formatTime(row['time_window_start']);
            final String endTime = _formatTime(row['time_window_end']);

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SectionCard(
                title: zoneName,
                subtitle: _dayLabel(dayRaw),
                child: Row(
                  children: <Widget>[
                    if (today)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Icon(Icons.access_time,
                        size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '$startTime – $endTime',
                      style: TextStyle(
                        fontSize: 13,
                        color: today
                            ? const Color(0xFF166534)
                            : Colors.grey[700],
                        fontWeight: today
                            ? FontWeight.w600
                            : FontWeight.normal,
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
