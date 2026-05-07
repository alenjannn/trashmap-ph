class AssignedTemplate {
  const AssignedTemplate({
    required this.assignmentId,
    required this.templateId,
    required this.name,
    required this.recurrenceDay,
    required this.startTime,
    required this.endTime,
    required this.templateActive,
    required this.assignedAtIso,
  });

  final String assignmentId;
  final String templateId;
  final String name;
  final String recurrenceDay;
  final String startTime;
  final String endTime;
  final bool templateActive;
  final String assignedAtIso;

  static AssignedTemplate? tryParse(Map<dynamic, dynamic> raw) {
    try {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw);
      final String? assignmentId = row['id'] as String?;
      final String? templateId = row['weekly_route_id'] as String?;
      final dynamic nested = row['weekly_routes'];
      if (assignmentId == null || templateId == null || nested is! Map<String, dynamic>) {
        return null;
      }
      final Map<String, dynamic> t = nested;
      final String? name = t['name'] as String?;
      final String? day = t['recurrence_day'] as String?;
      if (name == null || day == null) return null;
      
      final String start = (t['time_window_start'] ?? '06:00:00').toString();
      final String end = (t['time_window_end'] ?? '09:00:00').toString();
      final bool active = t['is_active'] as bool? ?? true;
      final String assignedAt =
          (row['assigned_at'] as String?) ?? DateTime.now().toUtc().toIso8601String();
      
      return AssignedTemplate(
        assignmentId: assignmentId,
        templateId: templateId,
        name: name,
        recurrenceDay: day,
        startTime: start,
        endTime: end,
        templateActive: active,
        assignedAtIso: assignedAt,
      );
    } catch (_) {
      return null;
    }
  }
}
