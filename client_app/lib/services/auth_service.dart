import 'package:client_app/models/app_user_role.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = SupabaseService.client;

  Stream<AuthState> authChanges() => _client.auth.onAuthStateChange;

  User? currentUser() => _client.auth.currentUser;

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<AppUserRole> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return fetchRoleForCurrentUser();
  }

  Future<AppUserRole> signUp({
    required String email,
    required String password,
    required AppUserRole role,
  }) async {
    final AuthResponse response = await _client.auth.signUp(
      email: email,
      password: password,
      data: <String, dynamic>{
        'requested_role': role.name,
      },
    );

    final User? user = response.user ?? _client.auth.currentUser;
    if (user != null) {
      await _client.from('app_user_profiles').upsert(<String, dynamic>{
        'user_id': user.id,
        'role': role.name,
      });
      return role;
    }

    return AppUserRole.citizen;
  }

  Future<AppUserRole> fetchRoleForCurrentUser() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return AppUserRole.citizen;

    final Map<String, dynamic>? profile = await _client
        .from('app_user_profiles')
        .select('role')
        .eq('user_id', user.id)
        .maybeSingle();

    return parseUserRole(profile?['role'] as String?);
  }
}
