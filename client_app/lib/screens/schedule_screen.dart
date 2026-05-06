import 'package:flutter/material.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/widgets/section_card.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
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
  List<Map<String, dynamic>> _schedules = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dynamic response = await SupabaseService.client
          .from('schedules')
          .select('id, collection_day, time_window_start, time_window_end, is_active, zones(name)')
          .eq('is_active', true)
          .limit(100);
      final List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(response as List<dynamic>);
      rows.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final String dayA = (a['collection_day'] ?? '').toString().toLowerCase();
        final String dayB = (b['collection_day'] ?? '').toString().toLowerCase();
        final int orderA = _dayOrder[dayA] ?? 99;
        final int orderB = _dayOrder[dayB] ?? 99;
        return orderA.compareTo(orderB);
      });

      if (!mounted) return;
      setState(() {
        _schedules = rows;
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
    final String normalized = rawDay.toLowerCase();
    final String today = weekdays[DateTime.now().weekday - 1];
    return normalized == today;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 12),
          child: Text(
            'Collection Schedule',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        if (_error != null)
          SectionCard(
            title: 'Schedule load error',
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB91C1C)),
            ),
          ),
        if (_error != null) const SizedBox(height: 10),
        if (_schedules.isEmpty)
          const SectionCard(
            title: 'No active schedule yet',
            child: Text('LGU has not published collection windows yet.'),
          )
        else
          ..._schedules.map((Map<String, dynamic> row) {
            final dynamic zone = row['zones'];
            final String zoneName = zone is Map<String, dynamic> ? (zone['name']?.toString() ?? 'Unassigned zone') : 'Unassigned zone';
            final String dayRaw = (row['collection_day'] ?? '').toString();
            final bool today = _isToday(dayRaw);
            return SectionCard(
              title: zoneName,
              subtitle: _dayLabel(dayRaw),
              child: Text(
                '${today ? "Today • " : ""}Window: ${(row['time_window_start'] ?? '--:--')} - ${(row['time_window_end'] ?? '--:--')}',
              ),
            );
          }),
      ],
    );
  }
}
