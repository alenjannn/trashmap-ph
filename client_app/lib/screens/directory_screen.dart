import 'package:flutter/material.dart';
import 'package:client_app/widgets/section_card.dart';

class DirectoryScreen extends StatelessWidget {
  const DirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 12),
          child: Text(
            'Recycler & Junk Shop Directory',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        SectionCard(
          title: 'GreenCycle MRF Hub',
          subtitle: '2.1 km away',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Accepted: Plastic, Paper, Aluminum'),
              SizedBox(height: 6),
              Text('Hours: 8:00 AM - 5:00 PM'),
              SizedBox(height: 6),
              Text('Contact: 0917-555-0199'),
            ],
          ),
        ),
        SectionCard(
          title: 'Barangay Eco Junk Shop',
          subtitle: '1.3 km away',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Accepted: Glass, Cardboard, Scrap Metal'),
              SizedBox(height: 6),
              Text('Hours: 9:00 AM - 4:00 PM'),
              SizedBox(height: 6),
              Text('Contact: 0921-324-1170'),
            ],
          ),
        ),
      ],
    );
  }
}
