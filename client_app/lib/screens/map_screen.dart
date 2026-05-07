import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

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
  final bool isPinDropMode;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late LatLng? _localSelectedPoint;
  List<_ReportPin> _liveReportPins = <_ReportPin>[];
  RealtimeChannel? _reportsChannel;
  _ReportPin? _selectedPin;
  final MapController _mapController = MapController();

  LatLng? _currentUserLocation;
  StreamSubscription<Position>? _positionStream;

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

    _initLocationTracking();
  }

  void _initLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        _currentUserLocation = LatLng(position.latitude, position.longitude);
      });
    });
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
    _positionStream?.cancel();
    _mapController.dispose();
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
      case 'biodegradable': return 'Biodegradable';
      case 'recyclable': return 'Recyclable';
      case 'special_hazardous': return 'Special / Hazardous';
      case 'mixed': return 'Mixed';
      default: return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    const LatLng qcCenter = LatLng(14.676, 121.0437);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _localSelectedPoint ?? qcCenter,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.tap,
            ),
            onTap: (_, __) {
              // Dismiss any open report-pin popup on map tap.
              // Pin placement is handled by the GestureDetector overlay below.
              if (_selectedPin != null) setState(() => _selectedPin = null);
            },
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.trashmapph.client_app',
            ),
            if (_currentUserLocation != null) ...[
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _currentUserLocation!,
                    radius: 20,
                    useRadiusInMeter: true,
                    color: Colors.blue.withOpacity(0.15),
                    borderColor: Colors.blue.withOpacity(0.3),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentUserLocation!,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            MarkerLayer(
              markers: _liveReportPins.map((pin) {
                return Marker(
                  point: pin.point,
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPin = pin),
                    child: Icon(
                      Icons.location_on_rounded,
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
                      Icons.place_rounded,
                      color: Color(0xFF1B4332),
                      size: 42,
                    ),
                  ),
                ],
              ),
            if (_selectedPin != null)
              MarkerLayer(
                markers: <Marker>[
                  Marker(
                    point: _selectedPin!.point,
                    width: 240,
                    height: 220,
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

        // Pin-drop overlay — sits above the map but below the controls.
        // Uses GestureDetector.onTapUp + camera.pointToLatLng for reliable
        // coordinate conversion regardless of flutter_map gesture state.
        if (widget.isPinDropMode)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (TapUpDetails details) {
                final Offset local = details.localPosition;
                final LatLng latLng = _mapController.camera.pointToLatLng(
                  math.Point(local.dx, local.dy),
                );
                setState(() {
                  _localSelectedPoint = latLng;
                  _selectedPin = null;
                });
                widget.onPinSelected?.call(latLng);
              },
            ),
          ),

        // Floating Header (IgnorePointer allows tapping the map through the gradient)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearAlignment.topCenter.toGradient(colors: [
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0),
                ]),
              ),
              child: Row(
                children: [
                  if (widget.isPinDropMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B4332),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1B4332).withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'TAP MAP TO SET PIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Integrated Map Controls (Right Side, Stacked)
        Positioned(
          right: 16,
          bottom: 220, // Moved significantly higher to ensure complete clearance from the nav bar
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Recenter Button
              _MapControlBtn(
                icon: Icons.my_location_rounded,
                onTap: () async {
                  if (_currentUserLocation != null) {
                    _mapController.move(_currentUserLocation!, 16);
                  } else {
                    // Fallback: Try a direct fetch if stream hasn't updated yet
                    try {
                      final pos = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high,
                        timeLimit: const Duration(seconds: 5),
                      );
                      final loc = LatLng(pos.latitude, pos.longitude);
                      setState(() => _currentUserLocation = loc);
                      _mapController.move(loc, 16);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Could not get location: $e'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              // 2. Zoom In
              _MapControlBtn(
                icon: Icons.add_rounded,
                onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
              ),
              const SizedBox(height: 8),
              // 3. Zoom Out
              _MapControlBtn(
                icon: Icons.remove_rounded,
                onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapControlBtn extends StatelessWidget {
  const _MapControlBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Icon(icon, color: const Color(0xFF1B4332), size: 22),
      ),
    );
  }
}

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
    final String desc = (pin.description?.isNotEmpty ?? false) ? pin.description! : '—';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAF9),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.delete_sweep_rounded, color: Color(0xFF1B4332), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Waste Details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: <Widget>[
                    _PopupRow(label: 'Category', value: wasteLabel),
                    const SizedBox(height: 8),
                    _PopupRow(label: 'Note', value: desc),
                    const SizedBox(height: 8),
                    _PopupRow(label: 'Location', value: '$lat, $lng'),
                  ],
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(16, 8),
          painter: _CaretPainter(),
        ),
        const SizedBox(height: 10), // Offset from pin
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
          width: 65,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B4332),
            ),
          ),
        ),
      ],
    );
  }
}

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
  }
  @override
  bool shouldRepaint(_CaretPainter oldDelegate) => false;
}

extension on Alignment {
  Gradient toGradient({required List<Color> colors}) {
    return LinearGradient(
      begin: this == Alignment.topCenter ? Alignment.topCenter : Alignment.bottomCenter,
      end: this == Alignment.topCenter ? Alignment.bottomCenter : Alignment.topCenter,
      colors: colors,
    );
  }
}
class LinearAlignment {
  static const Alignment topCenter = Alignment.topCenter;
}
