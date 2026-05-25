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
//   AuthService.authorizedGet()    — GET with auto token refresh
//   AuthService.authorizedPost()   — POST with auto token refresh
//
// CHANGES FROM ORIGINAL:
//   1. Added onSessionChanged callback — fired on every _saveTokens()
//      and clearTokens() call so the cache layer can invalidate itself
//      without a circular import.
//   2. No other logic changed.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static String get _base =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  // ── Session-change hook ───────────────────────────────────────────────────
  // Wire this up in main.dart (or AuthGate.initState) to invalidate the
  // HomeCache whenever the signed-in user changes:
  //
  //   AuthService.onSessionChanged = () => HomeCache.instance.invalidate();
  //
  // Keeping it as a plain callback (not an import) avoids a circular
  // dependency between auth_service ↔ home_cache.
  static VoidCallback? onSessionChanged;

  // ── In-memory cache so screens can call userId/userEmail synchronously ────
  static String _cachedUserId = '';
  static String _cachedEmail  = '';

  /// Call once in main() after SharedPreferences is available.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedUserId = prefs.getString('user_id') ?? '';
    _cachedEmail  = prefs.getString('email')   ?? '';

    final token = prefs.getString('access_token') ?? '';
    if (token.isNotEmpty) {
      await refreshAccessToken().timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
    }
  }

  // ── Sync getters ──────────────────────────────────────────────────────────

  static String get userId    => _cachedUserId;
  static String get userEmail => _cachedEmail;

  // ── Async helpers ─────────────────────────────────────────────────────────

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

  // ── Token storage ─────────────────────────────────────────────────────────

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
    _cachedUserId = userId;
    _cachedEmail  = email;
    onSessionChanged?.call(); // notify cache / any listener
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('email');
    _cachedUserId = '';
    _cachedEmail  = '';
    onSessionChanged?.call(); // notify cache / any listener
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  static Future<bool> refreshAccessToken() async {
    final prefs        = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final resp = await http.post(
        Uri.parse('$_base/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await prefs.setString('access_token',  data['access']  ?? '');
        await prefs.setString('refresh_token', data['refresh'] ?? refreshToken);
        return true;
      }

      if (resp.statusCode == 401) {
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final code = body['code'] as String? ?? '';
          if (code == 'token_not_valid') {
            await clearTokens();
          }
        } catch (_) {}
      }
    } on TimeoutException {
      // keep tokens
    } on Exception {
      // keep tokens
    }

    return false;
  }

  // ── Authorised request helpers ────────────────────────────────────────────

  static Future<http.Response> authorizedGet(String url) async {
    final token = await getAccessToken();
    var response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type':  'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (!refreshed) {
        final stillHasToken = await getAccessToken();
        if (stillHasToken == null || stillHasToken.isEmpty) {
          throw Exception('Session expired. Please sign in again.');
        }
      }
      final newToken = await getAccessToken();
      response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $newToken',
        },
      );
    }
    return response;
  }

  static Future<http.Response> authorizedPost(
      String url, Map<String, dynamic> body) async {
    final token = await getAccessToken();
    var response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type':  'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (!refreshed) {
        final stillHasToken = await getAccessToken();
        if (stillHasToken == null || stillHasToken.isEmpty) {
          throw Exception('Session expired. Please sign in again.');
        }
      }
      final newToken = await getAccessToken();
      response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $newToken',
        },
        body: jsonEncode(body),
      );
    }
    return response;
  }

  // ── Sign Up ───────────────────────────────────────────────────────────────

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

  // ── Sign In ───────────────────────────────────────────────────────────────

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

  // ── Sign Out ──────────────────────────────────────────────────────────────

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
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Fire-and-forget — always clear local state even if request fails.
    }
    await clearTokens(); // fires onSessionChanged internally
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    return {
      'success': false,
      'error':   'Google Sign-In is not available in this version. '
          'Please use email and password.',
    };
  }

  // ── Password Reset ────────────────────────────────────────────────────────

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

typedef VoidCallback = void Function();