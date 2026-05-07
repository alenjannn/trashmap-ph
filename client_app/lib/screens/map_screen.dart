import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ReportPin {
  const _ReportPin({
    required this.point,
    required this.wasteType,
    this.description,
  });
  final LatLng point;
  final String wasteType;
  final String? description;
}

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.selectedPoint,
    this.onPinSelected,
    this.isPinDropMode = false,
  });

  final LatLng? selectedPoint;
  final ValueChanged<LatLng>? onPinSelected;
  // When true, tapping the map places a new report pin.
  // Activated only via the "Go to Map tab to drop pin" button in ReportScreen.
  final bool isPinDropMode;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late LatLng? _localSelectedPoint;
  List<_ReportPin> _liveReportPins = <_ReportPin>[];
  RealtimeChannel? _reportsChannel;

  @override
  void initState() {
    super.initState();
    _localSelectedPoint = widget.selectedPoint;
    _loadLiveReportPins();
    _reportsChannel = SupabaseService.client
        .channel('mobile-map-reports-live-v1')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (_) => _loadLiveReportPins(),
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPoint != widget.selectedPoint) {
      _localSelectedPoint = widget.selectedPoint;
    }
  }

  @override
  void dispose() {
    final RealtimeChannel? channel = _reportsChannel;
    if (channel != null) {
      SupabaseService.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _loadLiveReportPins() async {
    final dynamic response = await SupabaseService.client
        .from('reports')
        .select('lat, lng, waste_type, description')
        .order('created_at', ascending: false)
        .limit(300);

    if (!mounted) return;
    final List<dynamic> rows = response as List<dynamic>;
    setState(() {
      _liveReportPins = rows.map((dynamic row) {
        return _ReportPin(
          point: LatLng((row['lat'] as num).toDouble(), (row['lng'] as num).toDouble()),
          wasteType: (row['waste_type'] as String?) ?? 'unknown',
          description: row['description'] as String?,
        );
      }).toList();
    });
  }

  void _showPinInfo(BuildContext ctx, _ReportPin pin) {
    final String label = _wasteLabel(pin.wasteType);
    showModalBottomSheet<void>(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Reported Garbage',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoRow(label: 'Waste Type', value: label),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Description',
                value: (pin.description?.isNotEmpty ?? false) ? pin.description! : '—',
              ),
            ],
          ),
        );
      },
    );
  }

  String _wasteLabel(String raw) {
    switch (raw) {
      case 'biodegradable':
        return 'Biodegradable';
      case 'recyclable':
        return 'Recyclable';
      case 'special_hazardous':
        return 'Special / Hazardous';
      case 'mixed':
        return 'Mixed';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    const LatLng qcCenter = LatLng(14.676, 121.0437);

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Community Waste Map',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.isPinDropMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Tap map to drop pin',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                  ),
                ),
            ],
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
                  onTap: widget.isPinDropMode
                      ? (_, LatLng latLng) {
                          setState(() => _localSelectedPoint = latLng);
                          widget.onPinSelected?.call(latLng);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Pin set: ${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      : null,
                ),
                children: <Widget>[
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.trashmapph.client_app',
                  ),
                  MarkerLayer(
                    markers: _liveReportPins.map((pin) {
                      return Marker(
                        point: pin.point,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _showPinInfo(context, pin),
                          child: const Icon(Icons.location_on, color: Color(0xFFDC2626), size: 34),
                        ),
                      );
                    }).toList(),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
          ),
        ),
      ],
    );
  }
}
