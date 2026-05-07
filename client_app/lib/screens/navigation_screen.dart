import 'dart:async';

import 'package:client_app/services/api_client.dart';
import 'package:client_app/services/step_engine.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/services/telemetry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.api,
    required this.routeId,
    required this.polyline,
    required this.stops,
    required this.steps,
    this.stepsWarning,
    this.geometryWarning,
  });

  final ApiClient api;
  final String routeId;
  final String? polyline;
  final List<dynamic> stops;
  final List<dynamic> steps;
  final String? stepsWarning;
  final String? geometryWarning;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final TelemetryService _telemetry;
  late StepEngine _engine;
  StreamSubscription<DriverFix>? _fixSub;

  final MapController _mapController = MapController();

  List<LatLng> _polylinePoints = <LatLng>[];
  NavState? _state;
  DriverFix? _lastFix;
  String? _error;
  bool _ending = false;
  bool _bannerSeen = false;

  // Guards against setState/mapController calls after dispose.
  bool _disposed = false;
  // When true, map camera follows GPS. Set false on manual pan, true on FAB tap.
  bool _autoFollow = true;
  // Throttle UI rebuilds to ~1/s instead of every GPS ping.
  DateTime? _lastStateUpdate;
  // Fetched once at init — required for route_progress inserts.
  String? _truckId;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _telemetry = TelemetryService(api: widget.api);
    _polylinePoints = _parsePolyline(widget.polyline);
    _engine = StepEngine(
      steps: widget.steps
          .map(TurnStep.tryParse)
          .whereType<TurnStep>()
          .toList(growable: false),
      stops: widget.stops
          .map(NavStop.tryParse)
          .whereType<NavStop>()
          .toList(growable: false),
    );
    _bootstrapTelemetry();
  }

  Future<void> _bootstrapTelemetry() async {
    // Fetch truck_id for this route — required on every route_progress insert.
    try {
      final List<dynamic> rows = await SupabaseService.client
          .from('routes')
          .select('truck_id')
          .eq('id', widget.routeId)
          .limit(1) as List<dynamic>;
      if (rows.isNotEmpty) {
        _truckId = (rows.first as Map<dynamic, dynamic>)['truck_id'] as String?;
      }
    } catch (_) {/* non-fatal; inserts will fail later with clear error */}

    final bool granted = await _telemetry.ensurePermission();
    if (_disposed || !mounted) return;
    if (!granted) {
      setState(() => _error = 'Location permission required for telemetry.');
      return;
    }
    await _telemetry.start(widget.routeId);
    if (_disposed || !mounted) return;
    _fixSub = _telemetry.fixes.listen(_onFix);
  }

  void _onFix(DriverFix fix) {
    if (_disposed) return;
    final NavState s = _engine.onPosition(LatLng(fix.lat, fix.lng), now: fix.timestamp);

    // Always update data fields (used even without setState).
    _lastFix = fix;
    _state = s;

    // Throttle full tree rebuild to at most once per 800 ms.
    final DateTime now = DateTime.now();
    if (_lastStateUpdate == null ||
        now.difference(_lastStateUpdate!).inMilliseconds >= 800) {
      _lastStateUpdate = now;
      if (mounted) setState(() {});
    }

    if (s.arrivedStopId != null) {
      unawaited(_writeArrived(s.arrivedStopId!));
    }

    // Move camera only when auto-follow is on.
    if (_autoFollow) {
      try {
        _mapController.move(LatLng(fix.lat, fix.lng), 17);
      } catch (_) {/* map not yet ready */}
    }
  }

  Future<void> _writeArrived(String stopId) async {
    final String? userId = SupabaseService.client.auth.currentUser?.id;
    final String nowIso = DateTime.now().toIso8601String();
    try {
      await SupabaseService.client
          .from('route_stops')
          .update(<String, dynamic>{'status': 'arrived'})
          .eq('id', stopId);

      final dynamic existing = await SupabaseService.client
          .from('route_progress')
          .select('id')
          .eq('route_id', widget.routeId)
          .eq('stop_id', stopId)
          .limit(1);
      if ((existing as List<dynamic>).isEmpty) {
        await SupabaseService.client.from('route_progress').insert(<String, dynamic>{
          'route_id': widget.routeId,
          'stop_id': stopId,
          'truck_id': _truckId,
          'status': 'arrived',
          'driver_id': userId,
          'updated_at': nowIso,
        });
      } else {
        await SupabaseService.client
            .from('route_progress')
            .update(<String, dynamic>{
              'status': 'arrived',
              'driver_id': userId,
              'updated_at': nowIso,
            })
            .eq('route_id', widget.routeId)
            .eq('stop_id', stopId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            'Arrived at ${_engine.stops.firstWhere((NavStop s) => s.id == stopId, orElse: () => _engine.stops.first).label}',
          ),
        ),
      );
    } catch (_) {/* keep nav running even if write fails */}
  }

  Future<void> _confirmStop(NavStop stop) async {
    final String? userId = SupabaseService.client.auth.currentUser?.id;
    final String nowIso = DateTime.now().toIso8601String();
    try {
      await SupabaseService.client
          .from('route_stops')
          .update(<String, dynamic>{'status': 'completed'})
          .eq('id', stop.id);

      final dynamic existing = await SupabaseService.client
          .from('route_progress')
          .select('id')
          .eq('route_id', widget.routeId)
          .eq('stop_id', stop.id)
          .limit(1);
      if ((existing as List<dynamic>).isEmpty) {
        await SupabaseService.client.from('route_progress').insert(<String, dynamic>{
          'route_id': widget.routeId,
          'stop_id': stop.id,
          'truck_id': _truckId,
          'status': 'completed',
          'confirmed_at': nowIso,
          'updated_at': nowIso,
          'driver_id': userId,
        });
      } else {
        await SupabaseService.client
            .from('route_progress')
            .update(<String, dynamic>{
              'status': 'completed',
              'confirmed_at': nowIso,
              'updated_at': nowIso,
              'driver_id': userId,
            })
            .eq('route_id', widget.routeId)
            .eq('stop_id', stop.id);
      }

      await SupabaseService.client.from('route_audit_logs').insert(<String, dynamic>{
        'route_id': widget.routeId,
        'stop_id': stop.id,
        'event_type': 'stop_completed',
        'actor_user_id': userId,
        'actor_role': 'driver',
        'area_label': stop.label,
        'metadata_json': <String, dynamic>{},
      });

      _engine.markStopCompleted(stop.id);
      if (!mounted) return;
      setState(() {
        _state = _state == null
            ? null
            : _engine.onPosition(LatLng(_lastFix?.lat ?? stop.point.latitude,
                _lastFix?.lng ?? stop.point.longitude));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Pickup confirmed for #${stop.order}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Confirm failed: $e')),
      );
    }
  }

  Future<void> _skipStop(NavStop stop) async {
    final String? userId = SupabaseService.client.auth.currentUser?.id;
    final String nowIso = DateTime.now().toIso8601String();
    try {
      await SupabaseService.client
          .from('route_stops')
          .update(<String, dynamic>{'status': 'skipped'})
          .eq('id', stop.id);

      final dynamic existing = await SupabaseService.client
          .from('route_progress')
          .select('id')
          .eq('route_id', widget.routeId)
          .eq('stop_id', stop.id)
          .limit(1);
      if ((existing as List<dynamic>).isEmpty) {
        await SupabaseService.client.from('route_progress').insert(<String, dynamic>{
          'route_id': widget.routeId,
          'stop_id': stop.id,
          'truck_id': _truckId,
          'status': 'skipped',
          'driver_id': userId,
          'updated_at': nowIso,
          'notes': 'Skipped from driver navigation.',
        });
      } else {
        await SupabaseService.client
            .from('route_progress')
            .update(<String, dynamic>{
              'status': 'skipped',
              'updated_at': nowIso,
              'driver_id': userId,
            })
            .eq('route_id', widget.routeId)
            .eq('stop_id', stop.id);
      }

      _engine.markStopSkipped(stop.id);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Skip failed: $e')),
      );
    }
  }

  Future<void> _onEndPressed() async {
    if (_ending) return;
    final NavState? s = _state;
    final int unresolved = s == null
        ? _engine.stops
            .where((NavStop x) => x.status == 'pending' || x.status == 'arrived')
            .length
        : (s.totalStops - s.completedStops);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('End route?'),
        content: Text(
          unresolved == 0
              ? 'All stops resolved. End the route now?'
              : 'You still have $unresolved unresolved stop(s). Ending now will mark them as missed pickups.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('End route'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _ending = true;
      _error = null;
    });

    try {
      await _telemetry.stop();
      await widget.api.endRoute(widget.routeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unresolved > 0 ? 'Route ended with $unresolved missed pickup(s).' : 'Route ended.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ending = false;
        _error = 'End route failed: $e';
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _fixSub?.cancel();
    unawaited(_telemetry.dispose());
    WakelockPlus.disable();
    super.dispose();
  }

  List<LatLng> _parsePolyline(String? p) {
    if (p == null || p.trim().isEmpty) return <LatLng>[];
    return p
        .split(';')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .map((String segment) {
          final List<String> parts = segment.split(',');
          if (parts.length != 2) return null;
          final double? lat = double.tryParse(parts[0]);
          final double? lng = double.tryParse(parts[1]);
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  String _fmtMeters(double m) {
    if (!m.isFinite || m < 0) return '—';
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';
  }

  String _fmtEta(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '—';
    final int mins = (seconds / 60).round();
    if (mins < 60) return '${mins} min';
    final int h = mins ~/ 60;
    final int rem = mins % 60;
    return '${h}h ${rem}m';
  }

  @override
  Widget build(BuildContext context) {
    final NavState? s = _state;
    final List<NavStop> stopList = _engine.stops;
    final TurnStep? currentStep = _engine.steps.isEmpty
        ? null
        : _engine.steps[(s?.currentStepIndex ?? 0).clamp(0, _engine.steps.length - 1)];

    final LatLng cameraCenter = _lastFix != null
        ? LatLng(_lastFix!.lat, _lastFix!.lng)
        : (_polylinePoints.isNotEmpty
            ? _polylinePoints[_polylinePoints.length ~/ 2]
            : (stopList.isNotEmpty ? stopList.first.point : const LatLng(14.676, 121.0437)));

    final NavStop? activeStop = (s?.activeStopIndex != null && stopList.isNotEmpty)
        ? stopList[s!.activeStopIndex!]
        : null;

    final int completed = s?.completedStops ?? stopList.where((NavStop x) => x.status == 'completed').length;
    final int total = s?.totalStops ?? stopList.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Navigating · $completed/$total stops',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'End route',
            onPressed: _ending ? null : _onEndPressed,
            icon: _ending
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.stop_circle_outlined, color: Color(0xFFFCA5A5)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _HudCard(
            instruction: currentStep?.instruction ?? 'Awaiting GPS…',
            distanceLabel: _fmtMeters(s?.distanceToStepM ?? 0),
            etaLabel: _fmtEta(s?.etaSeconds ?? 0),
            stopsLabel: '$completed / $total',
            offline: !_telemetry.isOnline,
            queued: _telemetry.queuedPings,
          ),
          if ((widget.stepsWarning?.isNotEmpty ?? false) && !_bannerSeen)
            _DismissBanner(
              text: 'Steps fallback: ${widget.stepsWarning}',
              onDismiss: () => setState(() => _bannerSeen = true),
            ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF7F1D1D),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          Expanded(
            child: Stack(
              children: <Widget>[
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: cameraCenter,
                    initialZoom: 16,
                    onPositionChanged: (MapPosition position, bool hasGesture) {
                      if (hasGesture && _autoFollow && !_disposed) {
                        setState(() => _autoFollow = false);
                      }
                    },
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'ph.trashmap.driver',
                    ),
                    if (_polylinePoints.length >= 2)
                      PolylineLayer(
                        polylines: <Polyline>[
                          Polyline(
                            points: _polylinePoints,
                            strokeWidth: 6,
                            color: const Color(0xFF60A5FA),
                            borderStrokeWidth: 1,
                            borderColor: const Color(0xFF1E3A8A),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: <Marker>[
                        for (final NavStop stop in stopList)
                          Marker(
                            point: stop.point,
                            width: 36,
                            height: 36,
                            child: _StopPin(
                              order: stop.order,
                              status: stop.status,
                              active: activeStop?.id == stop.id,
                            ),
                          ),
                        if (_lastFix != null)
                          Marker(
                            point: LatLng(_lastFix!.lat, _lastFix!.lng),
                            width: 44,
                            height: 44,
                            child: _TruckArrow(heading: _lastFix!.heading ?? 0),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                    onPressed: _lastFix == null
                        ? null
                        : () {
                            setState(() => _autoFollow = true);
                            _mapController.move(
                              LatLng(_lastFix!.lat, _lastFix!.lng),
                              17,
                            );
                          },
                    child: const Icon(Icons.my_location, size: 18),
                  ),
                ),
              ],
            ),
          ),
          _StopSheet(
            stops: stopList,
            activeStopId: activeStop?.id,
            onConfirm: _confirmStop,
            onSkip: _skipStop,
          ),
        ],
      ),
    );
  }
}

class _HudCard extends StatelessWidget {
  const _HudCard({
    required this.instruction,
    required this.distanceLabel,
    required this.etaLabel,
    required this.stopsLabel,
    required this.offline,
    required this.queued,
  });

  final String instruction;
  final String distanceLabel;
  final String etaLabel;
  final String stopsLabel;
  final bool offline;
  final int queued;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E40AF),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.turn_right, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      distanceLabel,
                      style: const TextStyle(
                        color: Color(0xFF93C5FD),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      instruction,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _HudPill(icon: Icons.access_time, label: 'ETA', value: etaLabel),
              const SizedBox(width: 8),
              _HudPill(icon: Icons.flag, label: 'Stops', value: stopsLabel),
              const SizedBox(width: 8),
              _HudPill(
                icon: offline ? Icons.cloud_off : Icons.cloud_done,
                label: offline ? 'Offline' : 'Live',
                value: queued > 0 ? '$queued queued' : 'OK',
                tone: offline ? _PillTone.warn : _PillTone.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _PillTone { neutral, success, warn }

class _HudPill extends StatelessWidget {
  const _HudPill({
    required this.icon,
    required this.label,
    required this.value,
    this.tone = _PillTone.neutral,
  });

  final IconData icon;
  final String label;
  final String value;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (tone) {
      case _PillTone.success:
        bg = const Color(0xFF064E3B);
        fg = const Color(0xFFA7F3D0);
        break;
      case _PillTone.warn:
        bg = const Color(0xFF78350F);
        fg = const Color(0xFFFCD34D);
        break;
      case _PillTone.neutral:
        bg = const Color(0xFF1E293B);
        fg = const Color(0xFFE2E8F0);
        break;
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: fg, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DismissBanner extends StatelessWidget {
  const _DismissBanner({required this.text, required this.onDismiss});
  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF78350F),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFCD34D), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFFEF3C7), fontSize: 12),
            ),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: const Icon(Icons.close, color: Color(0xFFFCD34D)),
          ),
        ],
      ),
    );
  }
}

class _StopPin extends StatelessWidget {
  const _StopPin({required this.order, required this.status, required this.active});
  final int order;
  final String status;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    switch (status) {
      case 'completed':
        bg = const Color(0xFF16A34A);
        break;
      case 'skipped':
        bg = const Color(0xFF6B7280);
        break;
      case 'missed':
        bg = const Color(0xFFDC2626);
        break;
      case 'arrived':
        bg = const Color(0xFFF59E0B);
        break;
      default:
        bg = active ? const Color(0xFF2563EB) : const Color(0xFF14B8A6);
    }
    return Container(
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$order',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TruckArrow extends StatelessWidget {
  const _TruckArrow({required this.heading});
  final double heading;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: heading * 3.1415926535 / 180,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.navigation, color: Color(0xFFFCD34D), size: 22),
      ),
    );
  }
}

class _StopSheet extends StatelessWidget {
  const _StopSheet({
    required this.stops,
    required this.activeStopId,
    required this.onConfirm,
    required this.onSkip,
  });

  final List<NavStop> stops;
  final String? activeStopId;
  final Future<void> Function(NavStop) onConfirm;
  final Future<void> Function(NavStop) onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, -4)),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Stops',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: stops.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int idx) {
                final NavStop stop = stops[idx];
                final bool active = stop.id == activeStopId;
                return _StopRow(
                  stop: stop,
                  active: active,
                  onConfirm: () => onConfirm(stop),
                  onSkip: () => onSkip(stop),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.active,
    required this.onConfirm,
    required this.onSkip,
  });

  final NavStop stop;
  final bool active;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final bool isResolved =
        stop.status == 'completed' || stop.status == 'skipped' || stop.status == 'missed';
    final Color bg = active
        ? const Color(0xFFEFF6FF)
        : (isResolved ? const Color(0xFFF8FAFC) : Colors.white);
    final Color border = active ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: active ? 1.5 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _StatusBadge(status: stop.status, order: stop.order),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '#${stop.order} ${stop.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stop.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _statusFg(stop.status),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          if (!isResolved) ...<Widget>[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Skip', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF166534),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Confirm', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF166534);
      case 'skipped':
        return const Color(0xFF6B7280);
      case 'missed':
        return const Color(0xFFB91C1C);
      case 'arrived':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF1E40AF);
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.order});
  final String status;
  final int order;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final IconData? overrideIcon;
    switch (status) {
      case 'completed':
        bg = const Color(0xFF16A34A);
        overrideIcon = Icons.check;
        break;
      case 'skipped':
        bg = const Color(0xFF94A3B8);
        overrideIcon = Icons.skip_next;
        break;
      case 'missed':
        bg = const Color(0xFFDC2626);
        overrideIcon = Icons.error_outline;
        break;
      case 'arrived':
        bg = const Color(0xFFF59E0B);
        overrideIcon = Icons.location_on;
        break;
      default:
        bg = const Color(0xFF14B8A6);
        overrideIcon = null;
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: overrideIcon != null
          ? Icon(overrideIcon, color: Colors.white, size: 16)
          : Text(
              '$order',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
            ),
    );
  }
}
