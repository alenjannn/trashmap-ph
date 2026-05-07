import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool _initialized = false;

  // Values from --dart-define flags; fall back to dev credentials if not provided.
  static const String _devUrl = 'https://feeifhnowujcvlumxklz.supabase.co';
  static const String _devAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlZWlmaG5vd3VqY3ZsdW14a2x6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5ODIyMDYsImV4cCI6MjA5MzU1ODIwNn0.kOPOT-0ueq8Yo2y2yHEhu49kU4UnDn0aFo-i2d7fdxo';

  static String get _url =>
      const String.fromEnvironment('SUPABASE_URL', defaultValue: _devUrl);
  static String get _anonKey => const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: _devAnonKey);

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (_initialized || !isConfigured) return;

    await Supabase.initialize(
      url: _url,
      anonKey: _anonKey,
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}
