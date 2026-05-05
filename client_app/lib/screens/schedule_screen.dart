import 'package:flutter/material.dart';
import 'package:client_app/widgets/section_card.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 12),
          child: Text(
            'Collection Schedule',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        SectionCard(
          title: 'Your Street',
          subtitle: 'Pilot barangay static data',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Street: Aurora St. Corner 5th Ave'),
              SizedBox(height: 6),
              Text('Collection Day: Tuesday / Friday'),
              SizedBox(height: 6),
              Text('Time Window: 6:00 AM - 9:00 AM'),
            ],
          ),
        ),
        SectionCard(
          title: 'Reminder Status',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(child: Text('Push reminder notifications')),
              Icon(Icons.notifications_active, color: Color(0xFF16A34A)),
            ],
          ),
        ),
        SectionCard(
          title: 'System Notice',
          child: Text('Holiday/Typhoon mode alerts will appear here once backend wiring is active.'),
        ),
      ],
    );
  }
}
