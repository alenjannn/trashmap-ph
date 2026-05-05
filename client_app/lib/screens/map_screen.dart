import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.selectedPoint,
    this.onPinSelected,
  });

  final LatLng? selectedPoint;
  final ValueChanged<LatLng>? onPinSelected;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late LatLng? _localSelectedPoint;

  @override
  void initState() {
    super.initState();
    _localSelectedPoint = widget.selectedPoint;
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPoint != widget.selectedPoint) {
      _localSelectedPoint = widget.selectedPoint;
    }
  }

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
                options: MapOptions(
                  initialCenter: _localSelectedPoint ?? qcCenter,
                  initialZoom: 14,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                  onTap: (_, LatLng latLng) {
                    setState(() {
                      _localSelectedPoint = latLng;
                    });
                    widget.onPinSelected?.call(latLng);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Pin set: ${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
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
                  if (_localSelectedPoint != null)
                    MarkerLayer(
                      markers: <Marker>[
                        Marker(
                          point: _localSelectedPoint!,
                          width: 46,
                          height: 46,
                          child: const Icon(
                            Icons.place,
                            color: Color(0xFF166534),
                            size: 38,
                          ),
                        ),
                      ],
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
