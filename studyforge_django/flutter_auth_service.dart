/// lib/services/auth_service.dart
/// Replaces the Supabase auth calls with plain JWT HTTP calls to Django.
/// Drop this file in place of the old one — no other Flutter files need changing.

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static String get _base => dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';

  // ── Token helpers ────────────────────────────────────────────────────────────

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
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('email');
  }

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

  /// Silently refresh the access token using the stored refresh token.
  /// Returns true on success, false if the session has expired.
  static Future<bool> refreshAccessToken() async {
    final prefs        = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null) return false;

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

  // ── Auth endpoints ───────────────────────────────────────────────────────────

  /// POST /auth/signup/
  static Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
  }) async {
    final resp = await http.post(
      Uri.parse('$_base/auth/signup/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(resp.body);
    if (resp.statusCode == 201) {
      await _saveTokens(
        access:  data['access_token'],
        refresh: data['refresh_token'],
        userId:  data['user_id'],
        email:   data['email'],
      );
      return {'success': true, 'user_id': data['user_id'], 'email': data['email']};
    }
    return {'success': false, 'error': data['detail'] ?? 'Sign-up failed.'};
  }

  /// POST /auth/signin/
  static Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    final resp = await http.post(
      Uri.parse('$_base/auth/signin/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200) {
      await _saveTokens(
        access:  data['access_token'],
        refresh: data['refresh_token'],
        userId:  data['user_id'],
        email:   data['email'],
      );
      return {'success': true, 'user_id': data['user_id'], 'email': data['email']};
    }
    return {'success': false, 'error': data['detail'] ?? 'Invalid email or password.'};
  }

  /// POST /auth/signout/
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
      // Fire-and-forget — always clear local state
    }
    await clearTokens();
  }
}
