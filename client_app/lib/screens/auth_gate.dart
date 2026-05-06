import 'dart:async';

import 'package:client_app/models/app_user_role.dart';
import 'package:client_app/screens/auth_screen.dart';
import 'package:client_app/screens/driver_shell.dart';
import 'package:client_app/screens/home_shell.dart';
import 'package:client_app/services/auth_service.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  StreamSubscription<AuthState>? _authSubscription;
  AppUserRole? _role;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _authSubscription = _authService.authChanges().listen((AuthState _) {
      _bootstrap();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    if (!SupabaseService.isConfigured) {
      if (!mounted) return;
      setState(() {
        _loadingRole = false;
        _role = null;
      });
      return;
    }

    final User? user = _authService.currentUser();
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loadingRole = false;
        _role = null;
      });
      return;
    }

    final AppUserRole role = await _authService.fetchRoleForCurrentUser();
    if (!mounted) return;
    setState(() {
      _role = role;
      _loadingRole = false;
    });
  }

  Future<void> _signOut() async {
    await _authService.signOut();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('TrashMap PH')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Supabase config missing.\nRun app with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_loadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_role == null) {
      return AuthScreen(authService: _authService);
    }

    if (_role == AppUserRole.driver) {
      return DriverShell(onSignOut: _signOut);
    }

    return HomeShell(
      onSignOut: _signOut,
      roleBadgeLabel: roleLabel(_role!),
    );
  }
}
