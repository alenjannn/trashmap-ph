import 'package:client_app/services/step_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('StepEngine', () {
    final List<TurnStep> sampleSteps = <TurnStep>[
      const TurnStep(
        instruction: 'Turn right',
        distanceM: 200,
        durationS: 60,
        point: LatLng(14.6760, 121.0440),
      ),
      const TurnStep(
        instruction: 'Continue straight',
        distanceM: 400,
        durationS: 90,
        point: LatLng(14.6770, 121.0450),
      ),
      const TurnStep(
        instruction: 'Arrive',
        distanceM: 50,
        durationS: 20,
        point: LatLng(14.6780, 121.0460),
      ),
    ];

    final List<NavStop> sampleStops = <NavStop>[
      const NavStop(
        id: 's1',
        order: 1,
        label: 'Block A',
        point: LatLng(14.6770, 121.0450),
        status: 'pending',
      ),
      const NavStop(
        id: 's2',
        order: 2,
        label: 'Block B',
        point: LatLng(14.6790, 121.0470),
        status: 'pending',
      ),
    ];

    test('advances current step when within step radius', () {
      final StepEngine engine = StepEngine(steps: sampleSteps, stops: sampleStops);
      final NavState first = engine.onPosition(const LatLng(14.6760, 121.0440));
      expect(first.currentStepIndex, 1, reason: 'first GPS at step 0 should advance to next pending step');
    });

    test('arrival requires 3s dwell within 50m', () {
      final StepEngine engine = StepEngine(steps: sampleSteps, stops: sampleStops);
      final DateTime t0 = DateTime.utc(2026, 1, 1, 8);

      final NavState within = engine.onPosition(const LatLng(14.6770, 121.0450), now: t0);
      expect(within.arrivedStopId, isNull, reason: 'first tick within radius starts dwell timer');

      final NavState dwellTooShort = engine
          .onPosition(const LatLng(14.6770, 121.0450), now: t0.add(const Duration(seconds: 1)));
      expect(dwellTooShort.arrivedStopId, isNull);

      final NavState arrived = engine
          .onPosition(const LatLng(14.6770, 121.0450), now: t0.add(const Duration(seconds: 4)));
      expect(arrived.arrivedStopId, 's1');
      expect(engine.stops.first.status, 'arrived');
    });

    test('confirm flips stop to completed and shifts active stop', () {
      final StepEngine engine = StepEngine(steps: sampleSteps, stops: sampleStops);
      engine.markStopCompleted('s1');
      final NavState s = engine.onPosition(const LatLng(14.6770, 121.0450));
      expect(engine.stops.first.status, 'completed');
      expect(s.activeStopIndex, 1);
      expect(s.completedStops, 1);
    });

    test('ETA includes per-stop dwell estimate', () {
      final StepEngine engine =
          StepEngine(steps: sampleSteps, stops: sampleStops, perStopDwellSeconds: 30);
      final NavState s = engine.onPosition(const LatLng(14.6755, 121.0435));
      expect(s.etaSeconds, greaterThan(0));
      expect(s.etaSeconds, greaterThanOrEqualTo(60.0 + 90.0 + 20.0));
    });
  });
}
