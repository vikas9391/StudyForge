import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/constants.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool    _loading = false;
  bool    _sent    = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    setState(() { _error = null; });

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/auth/reset-password/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (res.statusCode == 200) {
        setState(() { _sent = true; _loading = false; });
      } else {
        final body = jsonDecode(res.body);
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecond, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: _sent ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        const SizedBox(height: 40),

        // Success icon
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withOpacity(0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.accentGreen.withOpacity(0.35),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.mark_email_read_rounded,
            color: AppColors.accentGreen,
            size: 48,
          ),
        ),

        const SizedBox(height: 28),

        Text(
          'Check your inbox',
          style: AppText.display(22),
        ),

        const SizedBox(height: 10),

        Text(
          'If ${_emailController.text.trim()} has an account, '
              'a reset link is on its way.\n\n'
              'Tap the link in the email to open the app and set a new password.',
          textAlign: TextAlign.center,
          style: AppText.body,
        ),

        const SizedBox(height: 36),

        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
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
              child: Text(
                'Back to Sign In',
                style: AppText.subheading.copyWith(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),

        // Icon
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppColors.primaryGlow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withOpacity(0.20)),
          ),
          child: Icon(Icons.lock_reset_rounded,
              size: 26, color: AppColors.primary),
        ).animate().fadeIn(duration: 350.ms).scale(
          begin: const Offset(0.85, 0.85),
          curve: Curves.easeOutBack,
        ),

        const SizedBox(height: 20),

        Text('Forgot password?', style: AppText.display(24))
            .animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 8),

        Text(
          "Enter your email and we'll send a reset link.",
          style: AppText.body,
        ).animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 36),

        // Email label
        Text('Email address', style: AppText.label.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecond,
        )),
        const SizedBox(height: 6),

        // Email field
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: AppText.body.copyWith(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'you@example.com',
            hintStyle: AppText.body.copyWith(color: AppColors.textMuted, fontSize: 14),
            prefixIcon: Icon(Icons.email_outlined,
                color: AppColors.textSecond, size: 18),
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
          ),
        ).animate().fadeIn(delay: 200.ms),

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
                  const Icon(Icons.send_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Send Reset Link',
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