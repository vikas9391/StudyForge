// lib/services/auth_service.dart
// Full drop-in replacement for the Supabase-based AuthService.
// Matches every method and getter the screens call:
//   AuthService.userId        — sync getter (cached from SharedPreferences)
//   AuthService.userEmail     — sync getter (cached from SharedPreferences)
//   AuthService.signIn()      — POST /auth/signin/
//   AuthService.signUp()      — POST /auth/signup/
//   AuthService.signOut()     — POST /auth/signout/
//   AuthService.signInWithGoogle() — not supported, returns clear error
//   AuthService.resetPassword()    — POST /auth/reset-password/
//   AuthService.isLoggedIn()  — async check
//   AuthService.getUserId()   — async read from SharedPreferences
//   AuthService.getAccessToken()   — async read from SharedPreferences
//   AuthService.refreshAccessToken() — POST /auth/refresh/

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static String get _base =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  // ── In-memory cache so screens can call userId/userEmail synchronously ───────
  // Populated on signIn/signUp and on AuthService.init() at app startup.
  static String _cachedUserId = '';
  static String _cachedEmail  = '';

  /// Call once in main() after SharedPreferences is available.
  /// Loads cached userId and email so sync getters work immediately.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedUserId = prefs.getString('user_id') ?? '';
    _cachedEmail  = prefs.getString('email')   ?? '';
  }

  // ── Sync getters — used directly by screens ──────────────────────────────────

  /// Current user ID — sync, safe to call from build() or initState().
  static String get userId => _cachedUserId;

  /// Current user email — sync, safe to call from build() or initState().
  static String get userEmail => _cachedEmail;

  // ── Async helpers ────────────────────────────────────────────────────────────

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Token storage ─────────────────────────────────────────────────────────────

  static Future<void> _saveTokens({
    required String access,
    required String refresh,
    required String userId,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token',  access);
    await prefs.setString('refresh_token', refresh);
    await prefs.setString('user_id',       userId);
    await prefs.setString('email',         email);
    // Update cache so sync getters reflect new session immediately
    _cachedUserId = userId;
    _cachedEmail  = email;
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('email');
    _cachedUserId = '';
    _cachedEmail  = '';
  }

  // ── Token refresh ─────────────────────────────────────────────────────────────

  /// Silently refresh the access token. Returns true on success.
  static Future<bool> refreshAccessToken() async {
    final prefs        = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final resp = await http.post(
        Uri.parse('$_base/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await prefs.setString('access_token',  data['access']  ?? '');
        await prefs.setString('refresh_token', data['refresh'] ?? refreshToken);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Sign Up ───────────────────────────────────────────────────────────────────

  /// POST /auth/signup/
  /// Returns {'success': true, 'user_id': ..., 'email': ...}
  ///      or {'success': false, 'error': '...'}
  static Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/auth/signup/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 201) {
        await _saveTokens(
          access:  data['access_token']  ?? '',
          refresh: data['refresh_token'] ?? '',
          userId:  data['user_id']       ?? '',
          email:   data['email']         ?? email,
        );
        return {'success': true, 'user_id': data['user_id'], 'email': data['email']};
      }
      return {'success': false, 'error': data['detail'] ?? 'Sign-up failed.'};
    } catch (e) {
      return {'success': false, 'error': 'Cannot reach server: $e'};
    }
  }

  // ── Sign In ───────────────────────────────────────────────────────────────────

  /// POST /auth/signin/
  /// Returns {'success': true, 'user_id': ..., 'email': ...}
  ///      or {'success': false, 'error': '...'}
  static Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/auth/signin/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        await _saveTokens(
          access:  data['access_token']  ?? '',
          refresh: data['refresh_token'] ?? '',
          userId:  data['user_id']       ?? '',
          email:   data['email']         ?? email,
        );
        return {'success': true, 'user_id': data['user_id'], 'email': data['email']};
      }
      return {'success': false, 'error': data['detail'] ?? 'Invalid email or password.'};
    } catch (e) {
      return {'success': false, 'error': 'Cannot reach server: $e'};
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────────

  /// POST /auth/signout/ then clears local tokens.
  static Future<void> signOut() async {
    final prefs        = await SharedPreferences.getInstance();
    final accessToken  = prefs.getString('access_token')  ?? '';
    final refreshToken = prefs.getString('refresh_token') ?? '';

    try {
      await http.post(
        Uri.parse('$_base/auth/signout/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'refresh_token': refreshToken}),
      );
    } catch (_) {
      // Fire-and-forget — always clear local state even if request fails
    }
    await clearTokens();
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────────

  /// Google Sign-In via Supabase OAuth has been removed.
  /// To re-enable it you would need to configure social-django on the backend.
  /// For now this returns a clear error so the UI can show a message.
  static Future<Map<String, dynamic>> signInWithGoogle() async {
    return {
      'success': false,
      'error':   'Google Sign-In is not available in this version. '
          'Please use email and password.',
    };
  }

  // ── Password Reset ────────────────────────────────────────────────────────────

  /// POST /auth/reset-password/
  /// Django backend sends a reset email via Django's built-in password reset.
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/auth/reset-password/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (resp.statusCode == 200) {
        return {'success': true, 'message': 'Password reset email sent.'};
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return {'success': false, 'error': data['detail'] ?? 'Reset failed.'};
    } catch (e) {
      return {'success': false, 'error': 'Cannot reach server: $e'};
    }
  }
}