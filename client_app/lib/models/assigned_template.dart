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
      
      // weekly_routes uses integer hours (start_hour, end_hour). Render as HH:00:00
      // strings so existing UI code that expects time strings keeps working.
      final int startH = (t['start_hour'] is num)
          ? (t['start_hour'] as num).toInt()
          : int.tryParse((t['start_hour'] ?? '6').toString()) ?? 6;
      final int endH = (t['end_hour'] is num)
          ? (t['end_hour'] as num).toInt()
          : int.tryParse((t['end_hour'] ?? '12').toString()) ?? 12;
      final String start = '${startH.toString().padLeft(2, '0')}:00:00';
      final String end = '${endH.toString().padLeft(2, '0')}:00:00';
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
