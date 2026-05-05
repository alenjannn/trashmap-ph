import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool _initialized = false;

  static String get _url => const String.fromEnvironment('SUPABASE_URL');
  static String get _anonKey => const String.fromEnvironment('SUPABASE_ANON_KEY');

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
