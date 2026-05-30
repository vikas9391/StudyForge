import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static String get _base =>
      dotenv.env['API_BASE_URL'] ?? 'https://studyforge-api-08xo.onrender.com';

  static VoidCallback? onSessionChanged;

  static String _cachedUserId = '';
  static String _cachedEmail  = '';

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

  static String get userId    => _cachedUserId;
  static String get userEmail => _cachedEmail;

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
    onSessionChanged?.call();
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('email');
    _cachedUserId = '';
    _cachedEmail  = '';
    onSessionChanged?.call();
  }

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
          if (code == 'token_not_valid') await clearTokens();
        } catch (_) {}
      }
    } on TimeoutException {
      // keep tokens
    } on Exception {
      // keep tokens
    }

    return false;
  }

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

  static Future<void> signOut() async {
    final prefs        = await SharedPreferences.getInstance();
    final accessToken  = prefs.getString('access_token')  ?? '';
    final refreshToken = prefs.getString('refresh_token') ?? '';

    // Fire-and-forget server logout — don't let it block local cleanup
    http.post(
      Uri.parse('$_base/auth/signout/'),
      headers: {
        'Content-Type':  'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'refresh_token': refreshToken}),
    ).timeout(const Duration(seconds: 5)).catchError((_) {});

    // Always clear local tokens regardless of server response
    await clearTokens();
  }

  static final _googleSignIn = GoogleSignIn(
    clientId: dotenv.env['GOOGLE_SERVER_CLIENT_ID'],
    scopes: ['email', 'profile'],
  );

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return {'success': false, 'error': 'Sign-in cancelled.'};
      }

      final googleAuth = await googleUser.authentication;
      final idToken    = googleAuth.idToken;

      if (idToken == null) {
        return {'success': false, 'error': 'Failed to get Google token.'};
      }

      final resp = await http.post(
        Uri.parse('$_base/auth/google/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        await _saveTokens(
          access:  data['access_token']  ?? '',
          refresh: data['refresh_token'] ?? '',
          userId:  data['user_id'].toString(),
          email:   data['email']         ?? googleUser.email,
        );
        return {'success': true};
      }

      return {'success': false, 'error': data['detail'] ?? 'Google sign-in failed.'};
    } catch (e) {
      return {'success': false, 'error': 'Google sign-in error: $e'};
    }
  }

  // ── Password Reset ─────────────────────────────────────────────────────────

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

  // ── Password Reset Confirm ─────────────────────────────────────────────────

  static Future<Map<String, dynamic>> resetPasswordConfirm({
    required String uid,
    required String token,
    required String password,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/auth/reset-password/confirm/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token, 'password': password}),
      );
      if (resp.statusCode == 200) {
        return {'success': true};
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return {'success': false, 'error': data['detail'] ?? 'Reset failed.'};
    } catch (e) {
      return {'success': false, 'error': 'Cannot reach server: $e'};
    }
  }
}

typedef VoidCallback = void Function();