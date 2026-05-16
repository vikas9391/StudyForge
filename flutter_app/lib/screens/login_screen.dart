// lib/screens/login_screen.dart
// Premium animated login & sign-up screen using Supabase Auth.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../widgets/sf_logo.dart';
import '../main.dart' show fadeRoute;
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _auth         = AuthService();

  bool    _isLogin    = true;
  bool    _loading    = false;
  bool    _obscurePwd = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      if (_isLogin) {
        await _auth.signIn(
          email:    _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
      } else {
        await _auth.signUp(
          email:    _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fadeRoute(const HomeScreen()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [

                // ── Hero: logo + title ────────────────────────────────────
                const SFLogo(size: 80),
                const SizedBox(height: 18),

                Text('Studyforge', style: AppText.display(32))
                    .animate()
                    .fadeIn(delay: 200.ms)
                    .slideY(begin: 0.3, curve: Curves.easeOutCubic),

                const SizedBox(height: 6),

                Text('Turn documents into mastery', style: AppText.caption)
                    .animate().fadeIn(delay: 360.ms),

                const SizedBox(height: 40),

                // ── Form card ─────────────────────────────────────────────
                Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding:     const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color:        AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(24),
                    border:       Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.5),
                        blurRadius: 48,
                        offset:     const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [

                        // Header
                        Text(
                          _isLogin ? 'Welcome back' : 'Create account',
                          style: AppText.subheading,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isLogin
                              ? 'Sign in to continue your studies'
                              : 'Start learning smarter today',
                          style: AppText.caption,
                        ),
                        const SizedBox(height: 22),

                        // Error banner
                        if (_error != null) ...[
                          _ErrorBanner(message: _error!),
                          const SizedBox(height: 14),
                        ],

                        // Email field
                        TextFormField(
                          controller:   _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style:        AppText.body,
                          decoration: const InputDecoration(
                            labelText:  'Email address',
                            hintText:   'you@example.com',
                            prefixIcon: Icon(Icons.email_outlined,
                                color: AppColors.textMuted, size: 20),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Email is required';
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),

                        const SizedBox(height: 14),

                        // Password field
                        TextFormField(
                          controller:  _passwordCtrl,
                          obscureText: _obscurePwd,
                          style:       AppText.body,
                          decoration: InputDecoration(
                            labelText:  'Password',
                            hintText:   '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline_rounded,
                                color: AppColors.textMuted, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePwd
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.textMuted,
                                size:  20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePwd = !_obscurePwd),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Password is required';
                            if (!_isLogin && v.length < 6)
                              return 'Min 6 characters';
                            return null;
                          },
                        ),

                        const SizedBox(height: 26),

                        // Gradient submit button with glow
                        GestureDetector(
                          onTap: _loading ? null : _submit,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: _loading ? null : AppColors.primaryGrad,
                              color:    _loading ? AppColors.border : null,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: _loading
                                  ? []
                                  : [
                                      BoxShadow(
                                        color:      AppColors.primaryGlow,
                                        blurRadius: 18,
                                        offset:     const Offset(0, 6),
                                      ),
                                    ],
                            ),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(
                                        color:       Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.bolt_rounded,
                                            color: Colors.white, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          _isLogin ? 'Sign In' : 'Create Account',
                                          style: AppText.body.copyWith(
                                            color:      Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Toggle sign in / sign up
                        GestureDetector(
                          onTap: () => setState(() {
                            _isLogin = !_isLogin;
                            _error   = null;
                          }),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: AppText.caption,
                              children: [
                                TextSpan(
                                  text: _isLogin
                                      ? "Don't have an account? "
                                      : "Already have an account? ",
                                ),
                                TextSpan(
                                  text: _isLogin ? 'Sign Up' : 'Sign In',
                                  style: AppText.caption.copyWith(
                                    color:      AppColors.primaryLight,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.12),

              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error banner widget ───────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        AppColors.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: AppColors.accentRed.withOpacity(0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded,
            color: AppColors.accentRed, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppText.caption.copyWith(color: AppColors.accentRed),
          ),
        ),
      ]),
    ).animate().fadeIn().slideY(begin: -0.2);
  }
}
