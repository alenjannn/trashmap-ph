import 'dart:ui' as ui;

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
  _ReportPin? _selectedPin;

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
                  onTap: (_, LatLng latLng) {
                    if (widget.isPinDropMode) {
                      setState(() {
                        _localSelectedPoint = latLng;
                        _selectedPin = null;
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
                    } else {
                      // Dismiss any open popup on empty map tap
                      if (_selectedPin != null) setState(() => _selectedPin = null);
                    }
                  },
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
                          onTap: () => setState(() => _selectedPin = pin),
                          child: Icon(
                            Icons.location_on,
                            color: _selectedPin == pin
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFFDC2626),
                            size: 34,
                          ),
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
                  // Inline popup above selected pin
                  if (_selectedPin != null)
                    MarkerLayer(
                      markers: <Marker>[
                        Marker(
                          point: _selectedPin!.point,
                          width: 220,
                          height: 160,
                          alignment: Alignment.bottomCenter,
                          child: _PinPopupCard(
                            pin: _selectedPin!,
                            wasteLabel: _wasteLabel(_selectedPin!.wasteType),
                            onClose: () => setState(() => _selectedPin = null),
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

/// Inline popup card that floats above a pressed map pin.
/// Rendered as a Marker with alignment: Alignment.bottomCenter so it sits
/// directly above the geographic pin point.
class _PinPopupCard extends StatelessWidget {
  const _PinPopupCard({
    required this.pin,
    required this.wasteLabel,
    required this.onClose,
  });

  final _ReportPin pin;
  final String wasteLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final String lat = pin.point.latitude.toStringAsFixed(6);
    final String lng = pin.point.longitude.toStringAsFixed(6);
    final String desc =
        (pin.description?.isNotEmpty ?? false) ? pin.description! : '—';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Card body
        Container(
          width: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Reported Garbage',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              // Info rows
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  children: <Widget>[
                    _PopupRow(label: 'Type', value: wasteLabel),
                    const SizedBox(height: 4),
                    _PopupRow(label: 'Description', value: desc),
                    const SizedBox(height: 4),
                    _PopupRow(label: 'Location', value: '$lat, $lng'),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Caret pointing down to pin
        CustomPaint(
          size: const Size(16, 8),
          painter: _CaretPainter(),
        ),
      ],
    );
  }
}

class _PopupRow extends StatelessWidget {
  const _PopupRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small downward-pointing triangle connecting card to pin.
class _CaretPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = Colors.white;
    final ui.Path path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
    final Paint shadow = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, shadow);
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) => false;
}
