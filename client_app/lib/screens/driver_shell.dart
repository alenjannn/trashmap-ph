import 'package:flutter/material.dart';
import 'package:client_app/widgets/section_card.dart';

class DriverShell extends StatelessWidget {
  const DriverShell({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrashMap PH Driver'),
        actions: <Widget>[
          IconButton(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          SectionCard(
            title: 'Driver Console',
            child: Text(
              'Driver account active. Waiting for route dispatch assignments.',
            ),
          ),
          SizedBox(height: 12),
          SectionCard(
            title: 'Route Status',
            child: Text(
              'No active assigned route yet. Await dispatch sync.',
            ),
          ),
        ],
      ),
    );
  }
}
