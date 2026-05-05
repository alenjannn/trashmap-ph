import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const LatLng qcCenter = LatLng(14.676, 121.0437);
    const List<LatLng> mockPins = <LatLng>[
      LatLng(14.676, 121.0437),
      LatLng(14.6738, 121.0471),
      LatLng(14.6784, 121.0490),
    ];

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: const Text(
            'Community Waste Map',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: qcCenter,
                  initialZoom: 14,
                  interactionOptions: InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                ),
                children: <Widget>[
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.trashmapph.client_app',
                  ),
                  MarkerLayer(
                    markers: mockPins
                        .map(
                          (LatLng point) => Marker(
                            point: point,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Color(0xFFDC2626), size: 34),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
