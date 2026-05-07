import 'package:client_app/models/assigned_template.dart';
import 'package:client_app/screens/navigation_screen.dart';
import 'package:client_app/services/api_client.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/utils/route_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class TemplatePreviewScreen extends StatefulWidget {
  const TemplatePreviewScreen({super.key, required this.api, required this.template});

  final ApiClient api;
  final AssignedTemplate template;

  @override
  State<TemplatePreviewScreen> createState() => _TemplatePreviewScreenState();
}

class _PreviewStop {
  _PreviewStop({required this.order, required this.label, required this.point});
  final int order;
  final String label;
  final LatLng point;
}

class _TemplatePreviewScreenState extends State<TemplatePreviewScreen> {
  List<LatLng> _polylinePoints = <LatLng>[];
  List<_PreviewStop> _stops = <_PreviewStop>[];
  bool _loading = true;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreview();
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

  String _gateLabel(RouteGate gate) {
    switch (gate) {
      case RouteGate.onTime:
        return 'On time';
      case RouteGate.early:
        return 'Early';
      case RouteGate.late:
        return 'Late';
    }
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String manilaDate = routeDateInManila();
      // Use list + take-first to avoid 406 when multiple routes exist for same
      // template+date (e.g. duplicate materialization before unique constraint enforced).
      final List<dynamic> routeRows = await SupabaseService.client
          .from('routes')
          .select('id, polyline')
          .eq('template_id', widget.template.templateId)
          .eq('route_date', manilaDate)
          .order('created_at', ascending: false)
          .limit(1) as List<dynamic>;

      final Map<String, dynamic>? routeRow = routeRows.isEmpty
          ? null
          : Map<String, dynamic>.from(routeRows.first as Map<dynamic, dynamic>);

      final String? polylineStr = routeRow == null ? null : routeRow['polyline'] as String?;

      final List<dynamic> stopsRes = await SupabaseService.client
          .from('route_template_stops')
          .select('stop_order, collection_points ( label, lat, lng )')
          .eq('template_id', widget.template.templateId)
          .order('stop_order', ascending: true);

      final List<_PreviewStop> loaded = <_PreviewStop>[];
      for (final dynamic row in stopsRes) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(row as Map<dynamic, dynamic>);
        final int order = (m['stop_order'] as num?)?.toInt() ?? 0;
        final dynamic cp = m['collection_points'];
        if (cp is Map) {
          final Map<String, dynamic> c = Map<String, dynamic>.from(cp);
          final String label = (c['label'] as String?) ?? 'Stop';
          final double? lat = (c['lat'] as num?)?.toDouble();
          final double? lng = (c['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            loaded.add(_PreviewStop(order: order, label: label, point: LatLng(lat, lng)));
          }
        }
      }

      List<LatLng> points = _parsePolyline(polylineStr);
      if (points.length < 2 && loaded.length >= 2) {
        points = loaded.map((_PreviewStop s) => s.point).toList();
      }

      if (!mounted) return;
      setState(() {
        _polylinePoints = points;
        _stops = loaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _onStartPressed({bool force = false}) async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final StartTemplateResult result =
          await widget.api.startTemplate(widget.template.templateId, force: force);
      if (!mounted) return;

      if (result.precondition && result.gate != null) {
        setState(() => _starting = false);
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) {
            final bool early = result.gate == 'early';
            return AlertDialog(
              title: Text(early ? 'Start early?' : 'Start late?'),
              content: Text(
                early
                    ? 'You are starting your route early. Proceed to Start Route?'
                    : "You're late on starting your route. Proceed to Start Route?",
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
              ],
            );
          },
        );
        if (ok == true && mounted) {
          await _onStartPressed(force: true);
        }
        return;
      }

      if (!result.ok || result.routeId == null) {
        setState(() {
          _error = result.message ?? 'Start failed';
          _starting = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() => _starting = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext ctx) => NavigationScreen(
            api: widget.api,
            routeId: result.routeId!,
            polyline: result.polyline,
            stops: result.stops,
            steps: result.steps,
            stepsWarning: result.stepsWarning,
            geometryWarning: result.geometryWarning,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _starting = false;
      });
    }
  }

  String _capDay(String d) {
    if (d.isEmpty) return d;
    return d[0].toUpperCase() + d.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final RouteGate gate = computeRouteGate(
      recurrenceDay: widget.template.recurrenceDay,
      startHour: widget.template.startHour,
      endHour: widget.template.endHour,
    );

    final LatLng center = _polylinePoints.isNotEmpty
        ? _polylinePoints[_polylinePoints.length ~/ 2]
        : (_stops.isNotEmpty ? _stops.first.point : const LatLng(14.676, 121.0437));

    final String sh = widget.template.startHour.toString().padLeft(2, '0');
    final String eh = widget.template.endHour.toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template.name),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${_capDay(widget.template.recurrenceDay)} $sh:00–$eh:00',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Chip(
                        label: Text(_gateLabel(gate), style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 14,
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
                              strokeWidth: 5,
                              color: const Color(0xFF2563EB),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: _stops
                            .map(
                              (_PreviewStop s) => Marker(
                                point: s.point,
                                width: 36,
                                height: 36,
                                child: CircleAvatar(
                                  backgroundColor: const Color(0xFF14B8A6),
                                  child: Text(
                                    '${s.order}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _starting ? null : () => _onStartPressed(force: false),
                        child: _starting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Start Route'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
