import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// One ORS/OSRM/synthetic turn instruction sent by `/api/routes/templates/:id/start`.
class TurnStep {
  const TurnStep({
    required this.instruction,
    required this.distanceM,
    required this.durationS,
    required this.point,
    this.maneuverType,
  });

  final String instruction;
  final double distanceM;
  final double durationS;
  final LatLng point;
  final int? maneuverType;

  static TurnStep? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> m = Map<String, dynamic>.from(raw);
    final double? lat = (m['lat'] as num?)?.toDouble();
    final double? lng = (m['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return TurnStep(
      instruction: (m['instruction'] as String?) ?? 'Continue',
      distanceM: (m['distance_m'] as num?)?.toDouble() ?? 0,
      durationS: (m['duration_s'] as num?)?.toDouble() ?? 0,
      point: LatLng(lat, lng),
      maneuverType: (m['maneuver_type'] as num?)?.toInt(),
    );
  }
}

/// Stop position used for arrival detection (matches `route_stops` row).
class NavStop {
  const NavStop({
    required this.id,
    required this.order,
    required this.label,
    required this.point,
    required this.status,
  });

  final String id;
  final int order;
  final String label;
  final LatLng point;

  /// `pending` | `arrived` | `completed` | `skipped` | `missed`.
  final String status;

  NavStop copyWith({String? status}) => NavStop(
        id: id,
        order: order,
        label: label,
        point: point,
        status: status ?? this.status,
      );

  static NavStop? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> m = Map<String, dynamic>.from(raw);
    final String? id = m['id'] as String?;
    final double? lat = (m['lat'] as num?)?.toDouble();
    final double? lng = (m['lng'] as num?)?.toDouble();
    if (id == null || lat == null || lng == null) return null;
    return NavStop(
      id: id,
      order: (m['stop_order'] as num?)?.toInt() ?? 0,
      label: (m['label'] as String?) ?? 'Stop',
      point: LatLng(lat, lng),
      status: (m['status'] as String?) ?? 'pending',
    );
  }
}

/// Snapshot of nav state for the HUD. Pure data; UI binds to it.
class NavState {
  const NavState({
    required this.currentStepIndex,
    required this.nextStepIndex,
    required this.activeStopIndex,
    required this.distanceToStepM,
    required this.distanceToStopM,
    required this.etaSeconds,
    required this.totalDistanceM,
    required this.completedStops,
    required this.totalStops,
    required this.arrivedStopId,
  });

  final int currentStepIndex;
  final int? nextStepIndex;
  final int? activeStopIndex;
  final double distanceToStepM;
  final double distanceToStopM;

  /// Sum of remaining steps' `duration_s` plus a 30s/stop dwell estimate.
  final double etaSeconds;
  final double totalDistanceM;
  final int completedStops;
  final int totalStops;

  /// Set when a stop crossed the 50m + 3s arrival threshold this tick.
  /// One-shot signal; consumer maps to a server-side `arrived` flip.
  final String? arrivedStopId;
}

/// Distance + arrival logic for the navigation HUD.
///
/// Pure functions only — no GPS, no HTTP. Caller drives it via [onPosition]
/// and `markStop*` mutators, then reads `state` to render.
class StepEngine {
  StepEngine({
    required this.steps,
    required List<NavStop> stops,
    this.stepArrivalRadiusM = 25,
    this.stopArrivalRadiusM = 50,
    this.stopDwellSeconds = 3,
    this.perStopDwellSeconds = 30,
  }) : _stops = List<NavStop>.from(stops);

  final List<TurnStep> steps;
  List<NavStop> _stops;
  List<NavStop> get stops => List<NavStop>.unmodifiable(_stops);

  final double stepArrivalRadiusM;
  final double stopArrivalRadiusM;
  final int stopDwellSeconds;
  final int perStopDwellSeconds;

  int _currentStep = 0;
  DateTime? _stopWithinSince;
  String? _stopWithinId;

  static const Distance _distance = Distance();

  /// Updates internal state from a new GPS fix. Returns the resulting [NavState].
  NavState onPosition(LatLng pos, {DateTime? now}) {
    final DateTime ts = now ?? DateTime.now();

    if (steps.isNotEmpty) {
      while (_currentStep < steps.length - 1) {
        final double d = _distance.as(LengthUnit.Meter, pos, steps[_currentStep].point);
        if (d <= stepArrivalRadiusM) {
          _currentStep += 1;
        } else {
          break;
        }
      }
    }

    final int? activeStopIndex = _firstUnfinishedStopIndex();
    String? arrivedSignal;
    if (activeStopIndex != null) {
      final NavStop active = _stops[activeStopIndex];
      final double d = _distance.as(LengthUnit.Meter, pos, active.point);
      final bool within = d <= stopArrivalRadiusM;
      if (within) {
        if (_stopWithinId != active.id) {
          _stopWithinId = active.id;
          _stopWithinSince = ts;
        } else if (_stopWithinSince != null &&
            ts.difference(_stopWithinSince!).inSeconds >= stopDwellSeconds &&
            active.status == 'pending') {
          arrivedSignal = active.id;
          _stops[activeStopIndex] = active.copyWith(status: 'arrived');
        }
      } else if (_stopWithinId == active.id) {
        _stopWithinId = null;
        _stopWithinSince = null;
      }
    }

    return _buildState(pos: pos, arrivedSignal: arrivedSignal);
  }

  /// Driver tapped Confirm Pickup.
  void markStopCompleted(String stopId) => _setStopStatus(stopId, 'completed');

  /// Driver tapped Skip.
  void markStopSkipped(String stopId) => _setStopStatus(stopId, 'skipped');

  /// Server marks remaining stops missed at end-route.
  void markStopMissed(String stopId) => _setStopStatus(stopId, 'missed');

  void _setStopStatus(String stopId, String status) {
    _stops = _stops
        .map((NavStop s) => s.id == stopId ? s.copyWith(status: status) : s)
        .toList(growable: false);
    if (_stopWithinId == stopId) {
      _stopWithinId = null;
      _stopWithinSince = null;
    }
  }

  int? _firstUnfinishedStopIndex() {
    for (int i = 0; i < _stops.length; i++) {
      final String s = _stops[i].status;
      if (s == 'pending' || s == 'arrived') return i;
    }
    return null;
  }

  NavState _buildState({required LatLng pos, required String? arrivedSignal}) {
    final int? activeStopIndex = _firstUnfinishedStopIndex();
    final TurnStep? curStep = steps.isEmpty
        ? null
        : steps[math.min(_currentStep, steps.length - 1)];
    final int? nextStepIdx =
        steps.isEmpty || _currentStep + 1 >= steps.length ? null : _currentStep + 1;

    final double distToStep =
        curStep == null ? 0 : _distance.as(LengthUnit.Meter, pos, curStep.point);

    final double distToStop = activeStopIndex == null
        ? 0
        : _distance.as(LengthUnit.Meter, pos, _stops[activeStopIndex].point);

    double remainingStepsSeconds = 0;
    double remainingStepsMeters = 0;
    for (int i = math.max(_currentStep, 0); i < steps.length; i++) {
      remainingStepsSeconds += steps[i].durationS;
      remainingStepsMeters += steps[i].distanceM;
    }

    final int unfinishedStops = _stops
        .where((NavStop s) => s.status == 'pending' || s.status == 'arrived')
        .length;
    final int completedStops =
        _stops.where((NavStop s) => s.status == 'completed').length;

    final double dwellSeconds = unfinishedStops * perStopDwellSeconds.toDouble();
    final double etaSeconds = remainingStepsSeconds + dwellSeconds;

    return NavState(
      currentStepIndex: _currentStep,
      nextStepIndex: nextStepIdx,
      activeStopIndex: activeStopIndex,
      distanceToStepM: distToStep,
      distanceToStopM: distToStop,
      etaSeconds: etaSeconds,
      totalDistanceM: remainingStepsMeters,
      completedStops: completedStops,
      totalStops: _stops.length,
      arrivedStopId: arrivedSignal,
    );
  }
}
