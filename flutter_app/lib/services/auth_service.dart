// lib/services/auth_service.dart
// Wraps Supabase Auth — sign up, sign in, sign out.
// Free for up to 50,000 monthly active users on Supabase free tier.

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _client = Supabase.instance.client;

  // Currently signed-in user (null if not authenticated)
  User?   get currentUser => _client.auth.currentUser;
  String? get userId      => currentUser?.id;
  String? get userEmail   => currentUser?.email;

  // ── Sign Up ──────────────────────────────────────────────────────────────
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signUp(
      email:    email,
      password: password,
    );
    if (res.user == null) {
      throw 'Sign-up failed. Please try again.';
    }
  }

  // ── Sign In ──────────────────────────────────────────────────────────────
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email:    email,
        password: password,
      );
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    }
  }

  // ── Sign Out ─────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ── Human-readable error messages ────────────────────────────────────────
  String _friendlyError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('invalid login'))       return 'Incorrect email or password.';
    if (m.contains('already registered')) return 'An account already exists for this email.';
    if (m.contains('password'))           return 'Password must be at least 6 characters.';
    if (m.contains('email'))              return 'Please enter a valid email address.';
    return msg;
  }
}
