import 'package:client_app/models/assigned_template.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Next.js app URL (same machine: Android emulator `http://10.0.2.2:3000`, iOS sim `http://127.0.0.1:3000`).
class ApiClient {
  ApiClient({String? baseUrl})
      : baseUrl = _resolveBaseUrl(baseUrl);

  final String baseUrl;

  static const String _baseUrlFromEnvironment = String.fromEnvironment('API_BASE_URL');

  static String _resolveBaseUrl(String? override) {
    final String raw = override ?? _baseUrlFromEnvironment;
    if (raw.isEmpty) {
      throw StateError('API_BASE_URL dart-define required for ApiClient');
    }
    return raw.replaceAll(RegExp(r'/$'), '');
  }

  Dio _dio(String accessToken) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: <String, dynamic>{
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        validateStatus: (int? s) => s != null && s < 600,
      ),
    );
  }

  Future<String> _requireAccessToken() async {
    final Session? session = SupabaseService.client.auth.currentSession;
    final String? token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Not signed in');
    }
    return token;
  }

  /// Loads active weekly template assignments for the signed-in driver (Supabase RLS).
  Future<List<AssignedTemplate>> getMyAssignedTemplates() async {
    final String? userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return <AssignedTemplate>[];

    final dynamic res = await SupabaseService.client
        .from('route_template_assignments')
        .select(
          'id, template_id, assigned_at, route_templates ( id, name, recurrence_day, start_hour, end_hour, is_active )',
        )
        .eq('driver_id', userId)
        .eq('is_active', true);

    final List<dynamic> rows = res as List<dynamic>;
    final List<AssignedTemplate> out = <AssignedTemplate>[];
    for (final dynamic r in rows) {
      final AssignedTemplate? row = AssignedTemplate.tryParse(r as Map<dynamic, dynamic>);
      if (row != null && row.templateActive) {
        out.add(row);
      }
    }
    return out;
  }

  /// POST `/api/routes/templates/:id/start`. On [force]=false and 412, returns [StartTemplateResult.precondition].
  Future<StartTemplateResult> startTemplate(String templateId, {bool force = false}) async {
    final String token = await _requireAccessToken();
    final Response<dynamic> res = await _dio(token).post<dynamic>(
      '/api/routes/templates/$templateId/start',
      data: <String, dynamic>{'force': force},
    );
    final int code = res.statusCode ?? 0;
    final Map<String, dynamic> data = _asMap(res.data);

    if (code == 412) {
      final String gate = (data['gate'] as String?) ?? 'early';
      final String? message = data['message'] as String?;
      return StartTemplateResult.precondition(gate: gate, message: message);
    }

    if (code >= 200 && code < 300 && data['ok'] == true) {
      return StartTemplateResult.ok(
        routeId: data['routeId'] as String,
        polyline: data['polyline'] as String?,
        stops: data['stops'] as List<dynamic>? ?? <dynamic>[],
        steps: data['steps'] as List<dynamic>? ?? <dynamic>[],
        gate: data['gate'] as String?,
        message: data['message'] as String?,
        stepsWarning: data['stepsWarning'] as String?,
        geometryWarning: data['geometryWarning'] as String?,
      );
    }

    final String msg = (data['message'] as String?) ?? 'Start failed ($code)';
    return StartTemplateResult.error(message: msg, statusCode: code);
  }

  /// Turn-by-turn steps are returned from [startTemplate]. Reserved for a future dedicated endpoint.
  Future<Map<String, dynamic>?> getRouteDirections(String templateId) async {
    return <String, dynamic>{'templateId': templateId, 'note': 'Use startTemplate response steps.'};
  }

  Future<void> endRoute(String routeId, {String? actorUserId}) async {
    final String token = await _requireAccessToken();
    final Response<dynamic> res = await _dio(token).post<dynamic>(
      '/api/routes/$routeId/end',
      data: <String, dynamic>{
        if (actorUserId != null) 'actorUserId': actorUserId,
      },
    );
    final Map<String, dynamic> data = _asMap(res.data);
    if (res.statusCode == null || res.statusCode! >= 300 || data['ok'] != true) {
      throw StateError((data['message'] as String?) ?? 'End route failed');
    }
  }

  Future<void> postTelemetry(
    String routeId, {
    required double lat,
    required double lng,
    double? speedKmh,
    double? heading,
  }) async {
    final String token = await _requireAccessToken();
    final Response<dynamic> res = await _dio(token).post<dynamic>(
      '/api/routes/$routeId/telemetry',
      data: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (speedKmh != null) 'speed_kmh': speedKmh,
        if (heading != null) 'heading': heading,
      },
    );
    final Map<String, dynamic> data = _asMap(res.data);
    if (res.statusCode == null || res.statusCode! >= 300 || data['ok'] != true) {
      throw StateError((data['message'] as String?) ?? 'Telemetry failed');
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v));
    }
    return <String, dynamic>{};
  }
}

class StartTemplateResult {
  const StartTemplateResult._({
    required this.ok,
    this.precondition = false,
    this.routeId,
    this.polyline,
    this.stops = const <dynamic>[],
    this.steps = const <dynamic>[],
    this.gate,
    this.message,
    this.stepsWarning,
    this.geometryWarning,
    this.statusCode,
  });

  final bool ok;
  final bool precondition;
  final String? routeId;
  final String? polyline;
  final List<dynamic> stops;
  final List<dynamic> steps;
  final String? gate;
  final String? message;
  final String? stepsWarning;
  final String? geometryWarning;
  final int? statusCode;

  factory StartTemplateResult.ok({
    required String routeId,
    String? polyline,
    required List<dynamic> stops,
    required List<dynamic> steps,
    String? gate,
    String? message,
    String? stepsWarning,
    String? geometryWarning,
  }) {
    return StartTemplateResult._(
      ok: true,
      routeId: routeId,
      polyline: polyline,
      stops: stops,
      steps: steps,
      gate: gate,
      message: message,
      stepsWarning: stepsWarning,
      geometryWarning: geometryWarning,
    );
  }

  factory StartTemplateResult.precondition({required String gate, String? message}) {
    return StartTemplateResult._(ok: false, precondition: true, gate: gate, message: message);
  }

  factory StartTemplateResult.error({required String message, int? statusCode}) {
    return StartTemplateResult._(ok: false, message: message, statusCode: statusCode);
  }
}
