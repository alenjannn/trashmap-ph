import 'package:timezone/timezone.dart' as tz;

/// Matches server `computeGate` in `src/lib/route-gate.ts` (Asia/Manila).
enum RouteGate { onTime, early, late }

int _scheduledDayOrder(String recurrenceDay) {
  switch (recurrenceDay.toLowerCase()) {
    case 'sunday':
      return 0;
    case 'monday':
      return 1;
    case 'tuesday':
      return 2;
    case 'wednesday':
      return 3;
    case 'thursday':
      return 4;
    case 'friday':
      return 5;
    case 'saturday':
      return 6;
    default:
      return 0;
  }
}

/// Map Dart [DateTime.weekday] to server weekday order (Sun=0 .. Sat=6).
int _todayOrderFromWeekday(int dartWeekday) {
  return dartWeekday == DateTime.sunday ? 0 : dartWeekday;
}

RouteGate computeRouteGate({
  required String recurrenceDay,
  required int startHour,
  required int endHour,
}) {
  final int scheduled = _scheduledDayOrder(recurrenceDay);
  final tz.Location manila = tz.getLocation('Asia/Manila');
  final tz.TZDateTime now = tz.TZDateTime.now(manila);
  final int today = _todayOrderFromWeekday(now.weekday);
  final int hour = now.hour;

  if (today < scheduled) return RouteGate.early;
  if (today > scheduled) return RouteGate.late;
  if (hour < startHour) return RouteGate.early;
  if (hour >= endHour) return RouteGate.late;
  return RouteGate.onTime;
}

/// YYYY-MM-DD in Asia/Manila (for `routes.route_date`).
String routeDateInManila() {
  final tz.Location manila = tz.getLocation('Asia/Manila');
  final tz.TZDateTime now = tz.TZDateTime.now(manila);
  final String m = now.month.toString().padLeft(2, '0');
  final String d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}
