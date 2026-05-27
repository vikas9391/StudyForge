import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/constants.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String uid;
  final String token;

  const ResetPasswordScreen({
    super.key,
    required this.uid,
    required this.token,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pwController  = TextEditingController();
  final _pw2Controller = TextEditingController();
  bool _loading = false;
  bool _success = false;
  bool _showPw  = false;
  bool _showPw2 = false;
  String? _error;

  @override
  void dispose() {
    _pwController.dispose();
    _pw2Controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw  = _pwController.text.trim();
    final pw2 = _pw2Controller.text.trim();
    setState(() => _error = null);

    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/auth/reset-password/confirm/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid':      widget.uid,
          'token':    widget.token,
          'password': pw,
        }),
      );

      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        setState(() { _success = true; _loading = false; });
      } else {
        setState(() {
          _error   = body['detail'] ?? 'Something went wrong.';
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error   = 'Network error. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: _success ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Success icon
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.accentGreen.withOpacity(0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentGreen.withOpacity(0.35),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.check_rounded,
              color: AppColors.accentGreen,
              size: 44,
            ),
          ),

          const SizedBox(height: 24),

          Text('Password reset!', style: AppText.display(22)),

          const SizedBox(height: 10),

          Text(
            'You can now sign in with your new password.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),

          const SizedBox(height: 36),

          // Back to sign in
          GestureDetector(
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGrad,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.login_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Back to Sign In',
                      style: AppText.subheading.copyWith(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Icon
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppColors.primaryGlow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withOpacity(0.20)),
          ),
          child: Icon(Icons.lock_outline_rounded,
              size: 26, color: AppColors.primary),
        ).animate().fadeIn(duration: 350.ms).scale(
          begin: const Offset(0.85, 0.85),
          curve: Curves.easeOutBack,
        ),

        const SizedBox(height: 20),

        Text('Set new password', style: AppText.display(24))
            .animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 8),

        Text('Must be at least 8 characters.', style: AppText.body)
            .animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 32),

        // New password
        _PasswordField(
          label:    'New password',
          controller: _pwController,
          show:     _showPw,
          onToggle: () => setState(() => _showPw = !_showPw),
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 16),

        // Confirm password
        _PasswordField(
          label:    'Confirm password',
          controller: _pw2Controller,
          show:     _showPw2,
          onToggle: () => setState(() => _showPw2 = !_showPw2),
        ).animate().fadeIn(delay: 250.ms),

        const SizedBox(height: 12),

        // Error banner
        if (_error != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accentRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accentRed.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: AppColors.accentRed, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: AppText.caption.copyWith(
                        color: AppColors.accentRed, height: 1.4),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: -0.15),

        const SizedBox(height: 28),

        // Submit button
        GestureDetector(
          onTap: _loading ? null : _submit,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _loading
                    ? [AppColors.primary.withOpacity(0.5),
                  AppColors.primaryEnd.withOpacity(0.5)]
                    : [AppColors.primary, AppColors.primaryEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: _loading ? [] : [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: _loading
                  ? const SizedBox(
                height: 18, width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_reset_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Reset Password',
                    style: AppText.subheading.copyWith(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }
}

// ── Password field ────────────────────────────────────────────────────────────

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool show;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.show,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.label.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecond,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller:  controller,
          obscureText: !show,
          autocorrect: false,
          style: AppText.body.copyWith(
              fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: AppText.body.copyWith(
                color: AppColors.textMuted, fontSize: 14),
            prefixIcon: Icon(Icons.lock_outline_rounded,
                color: AppColors.textSecond, size: 18),
            suffixIcon: GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  show
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textSecond,
                  size: 18,
                ),
              ),
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
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
              borderSide: BorderSide(
                  color: AppColors.accentRed.withOpacity(0.6)),
            ),
          ),
        ),
      ],
    );
  }
}