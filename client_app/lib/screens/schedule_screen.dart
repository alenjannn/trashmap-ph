import 'package:flutter/material.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/widgets/section_card.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _schedules = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final response = await SupabaseService.client
        .from('schedules')
        .select('id, collection_day, time_window_start, time_window_end, is_active, zones(name)')
        .eq('is_active', true)
        .order('collection_day', ascending: true)
        .limit(50);

    if (!mounted) return;
    setState(() {
      _schedules = List<Map<String, dynamic>>.from(response as List<dynamic>);
      _loading = false;
    });
  }

  String _dayLabel(String raw) {
    if (raw.isEmpty) return 'Unknown day';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
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
        if (_schedules.isEmpty)
          const SectionCard(
            title: 'No active schedule yet',
            child: Text('LGU has not published collection windows yet.'),
          )
        else
          ..._schedules.map((Map<String, dynamic> row) {
            final dynamic zone = row['zones'];
            final String zoneName = zone is Map<String, dynamic> ? (zone['name']?.toString() ?? 'Unassigned zone') : 'Unassigned zone';
            return SectionCard(
              title: zoneName,
              subtitle: _dayLabel((row['collection_day'] ?? '').toString()),
              child: Text(
                'Window: ${(row['time_window_start'] ?? '--:--')} - ${(row['time_window_end'] ?? '--:--')}',
              ),
            );
          }),
      ],
    );
  }
}
