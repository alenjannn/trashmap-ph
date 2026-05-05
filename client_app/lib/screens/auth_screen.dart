import 'package:client_app/models/app_user_role.dart';
import 'package:client_app/services/auth_service.dart';
import 'package:flutter/material.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isBusy = false;
  AppUserRole _selectedRole = AppUserRole.citizen;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      if (_isSignUp) {
        await widget.authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          role: _selectedRole,
        );
      } else {
        await widget.authService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('AuthException: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'TrashMap PH',
                        style: TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSignUp ? 'Create account' : 'Sign in',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Citizen and driver role entry for Day 2 flow.',
                        style: TextStyle(color: Color(0xFF4B5563)),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (String? value) {
                          if (value == null || value.trim().isEmpty) return 'Email required';
                          if (!value.contains('@')) return 'Enter valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        validator: (String? value) {
                          if (value == null || value.length < 6) return 'Min 6 chars';
                          return null;
                        },
                      ),
                      if (_isSignUp) ...<Widget>[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<AppUserRole>(
                          initialValue: _selectedRole,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: AppUserRole.values
                              .where((AppUserRole role) => role != AppUserRole.admin)
                              .map((AppUserRole role) {
                            return DropdownMenuItem<AppUserRole>(
                              value: role,
                              child: Text(roleLabel(role)),
                            );
                          }).toList(),
                          onChanged: (AppUserRole? value) {
                            if (value == null) return;
                            setState(() {
                              _selectedRole = value;
                            });
                          },
                        ),
                      ],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isBusy ? null : _submit,
                          child: Text(_isBusy
                              ? 'Please wait...'
                              : (_isSignUp ? 'Create account' : 'Sign in')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isBusy
                            ? null
                            : () {
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _error = null;
                                });
                              },
                        child: Text(
                          _isSignUp
                              ? 'Already have account? Sign in'
                              : 'No account yet? Create one',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
