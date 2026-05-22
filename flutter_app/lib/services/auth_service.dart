// lib/services/auth_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _client = Supabase.instance.client;

  User?   get currentUser => _client.auth.currentUser;
  String? get userId      => currentUser?.id;
  String? get userEmail   => currentUser?.email;

  // ── Sign Up ──────────────────────────────────────────────────────────────
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signUp(email: email, password: password);
      if (res.user == null) throw 'Sign-up failed. Please try again.';
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    }
  }

  // ── Sign In ──────────────────────────────────────────────────────────────
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    }
  }

  // ── Google Sign-In ───────────────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        // Get this from Google Cloud Console → OAuth 2.0 → Web client ID
        serverClientId: '251420459771-f3f7klcnctoid41qomlev5898eb3kpba.apps.googleusercontent.com',
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) throw 'Google sign-in was cancelled.';

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) throw 'Google sign-in failed. No ID token.';

      await _client.auth.signInWithIdToken(
        provider:    OAuthProvider.google,
        idToken:     googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    } catch (e) {
      // Re-throw friendly strings as-is; wrap anything else
      if (e is String) rethrow;
      throw 'Google sign-in failed. Please try again.';
    }
  }

  // ── Password Reset ───────────────────────────────────────────────────────
  Future<void> resetPassword({required String email}) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.studyforge://login-callback',
      );
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    }
  }

// ── Sign Out ─────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
    }
  }

  // ── Friendly errors ──────────────────────────────────────────────────────
  String _friendlyError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('invalid login'))       return 'Incorrect email or password.';
    if (m.contains('already registered') ||
        m.contains('user already exists')) return 'An account already exists for this email.';
    if (m.contains('password'))            return 'Password must be at least 6 characters.';
    if (m.contains('email'))               return 'Please enter a valid email address.';
    return msg;
  }
}