// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../screens/forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onSignIn;
  const LoginScreen({super.key, this.onSignIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // Animation controller for shake-on-error
  late final AnimationController _shakeCtrl;
  late final Animation<double>    _shakeAnim;

  bool    _isLogin    = true;
  bool    _loading    = false;
  bool    _googleBusy = false;
  bool    _obscurePwd = true;
  bool    _rememberMe = false;
  String? _error;

  static const _kRememberKey = 'remember_me';
  static const _kEmailKey    = 'saved_email';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_kRememberKey) ?? false;
    if (remember) {
      final savedEmail = prefs.getString(_kEmailKey) ?? '';
      setState(() {
        _rememberMe = true;
        _emailCtrl.text = savedEmail;
      });
    }
  }

  Future<void> _saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberKey, _rememberMe);
    if (_rememberMe) {
      await prefs.setString(_kEmailKey, _emailCtrl.text.trim());
    } else {
      await prefs.remove(_kEmailKey);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ── Auth actions ───────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      _shakeCtrl.forward(from: 0);
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await _saveRememberMe();
      final result = _isLogin
          ? await AuthService.signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim())
          : await AuthService.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim());

      if (result['success'] == true) {
        if (mounted) widget.onSignIn?.call();
      } else {
        if (mounted) {
          setState(() => _error = result['error'] ?? 'Something went wrong');
          _shakeCtrl.forward(from: 0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        _shakeCtrl.forward(from: 0);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _googleBusy = true; _error = null; });
    try {
      final result = await AuthService.signInWithGoogle();
      if (result['success'] == true) {
        if (mounted) widget.onSignIn?.call();  // ← add this
      } else {
        if (mounted) setState(() => _error = result['error']);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }
  Future<void> _showForgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    String? dialogError;
    bool    sending = false;
    bool?   sent;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.border),
          ),
          title: Text(
            'Reset password',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "We'll send a reset link to your email address.",
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecond,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (dialogError != null) ...[
                _ErrorBanner(message: dialogError!),
                const SizedBox(height: 12),
              ],
              if (sent == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.accentGreen.withOpacity(0.35)),
                  ),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: AppColors.accentGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reset link sent! Check your inbox.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.accentGreen,
                        ),
                      ),
                    ),
                  ]),
                )
              else
                TextFormField(
                  controller:   emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: TextStyle(
                        fontSize: 14, color: AppColors.textSecond),
                    prefixIcon: Icon(Icons.email_outlined,
                        color: AppColors.textSecond, size: 18),
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                sent == true ? 'Done' : 'Cancel',
                style: TextStyle(
                  color: AppColors.textSecond,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (sent != true)
              GestureDetector(
                onTap: sending
                    ? null
                    : () async {
                  final email = emailCtrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    setD(() => dialogError =
                    'Enter a valid email address');
                    return;
                  }
                  setD(() {
                    sending     = true;
                    dialogError = null;
                  });
                  try {
                    await AuthService.resetPassword(email: email);
                    setD(() { sending = false; sent = true; });
                  } catch (e) {
                    setD(() {
                      sending     = false;
                      dialogError = e.toString();
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: sending
                        ? AppColors.primary.withOpacity(0.5)
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: sending
                      ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                      : const Text(
                    'Send link',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EDE8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [

              // ── Logo ───────────────────────────────────────────────────
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.25)),
                ),
                child: Center(
                  child: Icon(Icons.bolt_rounded,
                      size: 38, color: AppColors.primary),
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scale(
                begin: const Offset(0.85, 0.85),
                curve: Curves.easeOutBack,
              ),

              const SizedBox(height: 16),

              Text(
                'Studyforge',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              )
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideY(begin: 0.15, curve: Curves.easeOutCubic),

              const SizedBox(height: 4),

              Text(
                'Turn documents into mastery',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecond,
                    fontWeight: FontWeight.w400),
              ).animate().fadeIn(delay: 180.ms, duration: 350.ms),

              const SizedBox(height: 32),

              // ── Form card (shake wrapper) ──────────────────────────────
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) {
                  final dx = (_shakeAnim.value * 12) *
                      ((_shakeAnim.value * 6).toInt().isEven ? 1 : -1);
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _buildFormContent(),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 250.ms, duration: 400.ms)
                  .slideY(begin: 0.1, curve: Curves.easeOutCubic),

              const SizedBox(height: 32),

              // ── Trust line ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 12,
                      color: AppColors.textSecond.withOpacity(0.5)),
                  const SizedBox(width: 5),
                  Text(
                    'Secured with JWT Auth',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecond.withOpacity(0.5),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 450.ms, duration: 350.ms),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Form content (keyed so AnimatedSwitcher fires on mode toggle) ──────────
  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        key: ValueKey(_isLogin),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // Header
          Text(
            _isLogin ? 'Welcome back' : 'Create account',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isLogin
                ? 'Sign in to continue your studies'
                : 'Start learning smarter today',
            style: TextStyle(fontSize: 12, color: AppColors.textSecond),
          ),
          const SizedBox(height: 20),

          // Error
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 14),
          ],

          // Google button
          _GoogleButton(
            busy:    _googleBusy,
            onTap:   _signInWithGoogle,
          ),
          const SizedBox(height: 16),

          // Divider
          Row(children: [
            Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'or continue with email',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecond),
              ),
            ),
            Expanded(child: Divider(color: AppColors.border)),
          ]),
          const SizedBox(height: 16),

          // Email
          _buildLabel('Email address'),
          const SizedBox(height: 6),
          TextFormField(
            controller:   _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(
                fontSize: 14, color: AppColors.textPrimary),
            decoration: _fieldDecoration(
              hint:   'you@example.com',
              prefix: Icons.email_outlined,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              if (!v.contains('@'))       return 'Enter a valid email';
              return null;
            },
          ),

          const SizedBox(height: 14),

          // Password
          _buildLabel('Password'),
          const SizedBox(height: 6),
          TextFormField(
            controller:  _passwordCtrl,
            obscureText: _obscurePwd,
            style: TextStyle(
                fontSize: 14, color: AppColors.textPrimary),
            decoration: _fieldDecoration(
              hint:   '••••••••',
              prefix: Icons.lock_outline_rounded,
              suffix: GestureDetector(
                onTap: () =>
                    setState(() => _obscurePwd = !_obscurePwd),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    _obscurePwd
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textSecond,
                    size: 18,
                  ),
                ),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (!_isLogin && v.length < 6) return 'Min 6 characters';
              return null;
            },
          ),

          const SizedBox(height: 12),

          // Remember me + Forgot password row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Remember me
              GestureDetector(
                onTap: () =>
                    setState(() => _rememberMe = !_rememberMe),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: _rememberMe
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: _rememberMe
                              ? AppColors.primary
                              : AppColors.border,
                          width: 1.5,
                        ),
                      ),
                      child: _rememberMe
                          ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 12)
                          : null,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Remember me',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecond,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Forgot password (login mode only)
              if (_isLogin)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                  ),
                  child: Text(
                    'Forgot password?',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Submit
          GestureDetector(
            onTap: _loading ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 50,
              decoration: BoxDecoration(
                color: _loading
                    ? AppColors.primary.withOpacity(0.5)
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: _loading
                    ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 7),
                    Text(
                      _isLogin ? 'Sign In' : 'Create Account',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Toggle
          GestureDetector(
            onTap: () => setState(() {
              _isLogin = !_isLogin;
              _error   = null;
            }),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecond),
                children: [
                  TextSpan(
                    text: _isLogin
                        ? "Don't have an account? "
                        : "Already have an account? ",
                  ),
                  TextSpan(
                    text: _isLogin ? 'Sign Up' : 'Sign In',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecond,
      letterSpacing: 0.1,
    ),
  );

  InputDecoration _fieldDecoration({
    required String  hint,
    required IconData prefix,
    Widget?          suffix,
  }) =>
      InputDecoration(
        hintText:    hint,
        hintStyle:   TextStyle(fontSize: 14, color: AppColors.textSecond),
        prefixIcon:  Icon(prefix, color: AppColors.textSecond, size: 18),
        suffixIcon:  suffix,
        filled:      true,
        fillColor:   AppColors.bg,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
          BorderSide(color: AppColors.accentRed.withOpacity(0.6)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
          BorderSide(color: AppColors.accentRed, width: 1.5),
        ),
      );
}

// ── Google button ─────────────────────────────────────────────────────────────
class _GoogleButton extends StatelessWidget {
  final bool     busy;
  final VoidCallback onTap;
  const _GoogleButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: busy
              ? SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
          )
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Google "G" logo via coloured icon approximation
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(colors: [
                    Color(0xFF4285F4),
                    Color(0xFF34A853),
                    Color(0xFFFBBC05),
                    Color(0xFFEA4335),
                    Color(0xFF4285F4),
                  ]),
                ),
                child: const Center(
                  child: Text(
                    'G',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Continue with Google',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.30)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded,
            color: AppColors.accentRed, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
                fontSize: 12, color: AppColors.accentRed, height: 1.4),
          ),
        ),
      ]),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.15);
  }
}