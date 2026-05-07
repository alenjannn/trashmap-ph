class AssignedTemplate {
  const AssignedTemplate({
    required this.assignmentId,
    required this.templateId,
    required this.name,
    required this.recurrenceDay,
    required this.startHour,
    required this.endHour,
    required this.templateActive,
    required this.assignedAtIso,
  });

  final String assignmentId;
  final String templateId;
  final String name;
  final String recurrenceDay;
  final int startHour;
  final int endHour;
  final bool templateActive;
  final String assignedAtIso;

  static AssignedTemplate? tryParse(Map<dynamic, dynamic> raw) {
    try {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw);
      final String? assignmentId = row['id'] as String?;
      final String? templateId = row['template_id'] as String?;
      final dynamic nested = row['route_templates'];
      if (assignmentId == null || templateId == null || nested is! Map<String, dynamic>) {
        return null;
      }
      final Map<String, dynamic> t = nested;
      final String? name = t['name'] as String?;
      final String? day = t['recurrence_day'] as String?;
      if (name == null || day == null) return null;
      final int start = (t['start_hour'] as num?)?.toInt() ?? 6;
      final int end = (t['end_hour'] as num?)?.toInt() ?? 12;
      final bool active = t['is_active'] as bool? ?? true;
      final String assignedAt =
          (row['assigned_at'] as String?) ?? DateTime.now().toUtc().toIso8601String();
      return AssignedTemplate(
        assignmentId: assignmentId,
        templateId: templateId,
        name: name,
        recurrenceDay: day,
        startHour: start,
        endHour: end,
        templateActive: active,
        assignedAtIso: assignedAt,
      );
    } catch (_) {
      return null;
    }
  }
}
