import 'dart:async';
import 'dart:collection';

import 'package:client_app/services/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

/// Single GPS sample observed by the driver app.
class DriverFix {
  const DriverFix({
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.speedKmh,
    this.heading,
    this.accuracyM,
  });

  final double lat;
  final double lng;
  final DateTime timestamp;
  final double? speedKmh;
  final double? heading;
  final double? accuracyM;

  Map<String, dynamic> toQueueJson() => <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'speed_kmh': speedKmh,
        'heading': heading,
        'ts': timestamp.toIso8601String(),
      };
}

class _PendingPing {
  _PendingPing(this.fix, this.attempt);
  final DriverFix fix;
  int attempt;
}

/// GPS streamer + 5-second telemetry POST loop with offline queue.
///
/// Lifecycle:
/// * `start(routeId)` requests permission, opens a position stream, begins the
///   5s post timer, and listens for connectivity changes.
/// * `stop()` cancels everything and flushes pending pings if online.
///
/// Offline behavior: if a POST fails or `Connectivity.checkConnectivity()`
/// reports `none`, the fix is appended to an in-memory queue (capped at 240,
/// ~20 min at 5s interval). When connectivity returns, the queue is drained
/// FIFO; failures push items back to the head with `attempt += 1` (max 5).
class TelemetryService {
  TelemetryService({required this.api});

  final ApiClient api;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _postTimer;

  String? _routeId;
  DriverFix? _lastFix;
  bool _online = true;
  bool _draining = false;
  bool _started = false;

  final Queue<_PendingPing> _queue = Queue<_PendingPing>();
  static const int _maxQueueLen = 240;
  static const int _maxAttempts = 5;

  final StreamController<DriverFix> _fixController =
      StreamController<DriverFix>.broadcast();
  Stream<DriverFix> get fixes => _fixController.stream;

  bool get isRunning => _started;
  int get queuedPings => _queue.length;
  bool get isOnline => _online;

  /// Asks for location permission. Returns `true` if granted.
  Future<bool> ensurePermission() async {
    final bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<void> start(String routeId) async {
    if (_started) return;
    _started = true;
    _routeId = routeId;

    final List<ConnectivityResult> initial = await Connectivity().checkConnectivity();
    _online = !initial.contains(ConnectivityResult.none);

    _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition, onError: (_) {/* swallow */});

    _postTimer = Timer.periodic(const Duration(seconds: 5), (_) => _postLatest());
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _positionSub?.cancel();
    await _connectivitySub?.cancel();
    _postTimer?.cancel();
    _positionSub = null;
    _connectivitySub = null;
    _postTimer = null;
    if (_online) {
      await _drainQueue();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _fixController.close();
  }

  void _onPosition(Position p) {
    final DriverFix fix = DriverFix(
      lat: p.latitude,
      lng: p.longitude,
      timestamp: p.timestamp,
      speedKmh: p.speed.isFinite && p.speed >= 0 ? p.speed * 3.6 : null,
      heading: p.heading.isFinite && p.heading >= 0 ? p.heading : null,
      accuracyM: p.accuracy.isFinite ? p.accuracy : null,
    );
    _lastFix = fix;
    if (!_fixController.isClosed) {
      _fixController.add(fix);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final bool nowOnline = !results.contains(ConnectivityResult.none);
    final bool wasOffline = !_online;
    _online = nowOnline;
    if (nowOnline && wasOffline) {
      unawaited(_drainQueue());
    }
  }

  Future<void> _postLatest() async {
    final String? routeId = _routeId;
    final DriverFix? fix = _lastFix;
    if (routeId == null || fix == null) return;

    if (!_online) {
      _enqueue(fix);
      return;
    }

    try {
      await api.postTelemetry(
        routeId,
        lat: fix.lat,
        lng: fix.lng,
        speedKmh: fix.speedKmh,
        heading: fix.heading,
      );
      if (_queue.isNotEmpty) {
        unawaited(_drainQueue());
      }
    } catch (_) {
      _enqueue(fix);
    }
  }

  void _enqueue(DriverFix fix) {
    if (_queue.length >= _maxQueueLen) {
      _queue.removeFirst();
    }
    _queue.add(_PendingPing(fix, 0));
  }

  Future<void> _drainQueue() async {
    if (_draining || !_online) return;
    final String? routeId = _routeId;
    if (routeId == null) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && _online) {
        final _PendingPing ping = _queue.removeFirst();
        try {
          await api.postTelemetry(
            routeId,
            lat: ping.fix.lat,
            lng: ping.fix.lng,
            speedKmh: ping.fix.speedKmh,
            heading: ping.fix.heading,
          );
        } catch (_) {
          ping.attempt += 1;
          if (ping.attempt < _maxAttempts) {
            _queue.addFirst(ping);
            break;
          }
        }
      }
    } finally {
      _draining = false;
    }
  }
}
