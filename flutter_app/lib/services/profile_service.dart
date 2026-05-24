// lib/services/profile_service.dart
// Handles all profile and admin API calls.
// CHANGES FROM ORIGINAL:
//   1. Removed Supabase import — token now read from SharedPreferences
//   2. Added trailing slashes to all endpoints (Django requires them)

import 'package:dio/dio.dart' as diolib;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

class ProfileService {
  static final ProfileService _i = ProfileService._();
  factory ProfileService() => _i;
  ProfileService._();

  String get _base => dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  // ── Token helper — reads JWT from SharedPreferences (NOT Supabase) ─────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<diolib.Dio> _getDio() async {
    final token = await _getToken();
    return diolib.Dio(diolib.BaseOptions(
      baseUrl:        _base,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ));
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<UserProfile> getProfile(String userId) async {
    final dio = await _getDio();
    try {
      final r = await dio.get('/profile/$userId/');
      return UserProfile.fromJson(r.data as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  /// Update name, bio, and/or phone. Pass null to leave a field unchanged.
  Future<UserProfile> updateProfile(
    String userId, {
    String? fullName,
    String? bio,
    String? phone,
    String? avatarUrl,
  }) async {
    final dio = await _getDio();
    try {
      final body = <String, dynamic>{};
      if (fullName  != null) body['full_name']  = fullName;
      if (bio       != null) body['bio']        = bio;
      if (phone     != null) body['phone']      = phone;
      if (avatarUrl != null) body['avatar_url'] = avatarUrl;
      if (body.isEmpty) throw 'Nothing to update.';

      final r = await dio.put('/profile/$userId/', data: body);
      return UserProfile.fromJson(
          (r.data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<List<Map<String, dynamic>>> getUserHistory(String userId) async {
    final dio = await _getDio();
    try {
      final r = await dio.get('/profile/$userId/history/');
      return List<Map<String, dynamic>>.from(
          (r.data as Map)['sessions'] as List? ?? []);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  // ── Admin ─────────────────────────────────────────────────────────────────

  Future<AdminStats> getAdminStats() async {
    final dio = await _getDio();
    try {
      final r = await dio.get('/admin/stats/');
      return AdminStats.fromJson(r.data as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<Map<String, dynamic>> getAdminUsers(
      {int page = 1, int limit = 20}) async {
    final dio = await _getDio();
    try {
      final r = await dio.get('/admin/users/',
          queryParameters: {'page': page, 'limit': limit});
      return r.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<Map<String, dynamic>> getAdminUserDetail(String userId) async {
    final dio = await _getDio();
    try {
      final r = await dio.get('/admin/users/$userId/');
      return r.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> adminDeleteResult(String resultId) async {
    final dio = await _getDio();
    try {
      await dio.delete('/admin/results/$resultId/');
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<bool> adminToggleAdmin(String userId) async {
    final dio = await _getDio();
    try {
      final r = await dio.put('/admin/users/$userId/toggle-admin/');
      return (r.data as Map)['is_admin'] as bool? ?? false;
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  String _err(diolib.DioException e) {
    if (e.response != null) {
      final d = (e.response?.data as Map?)?['detail'];
      if (d != null) return d.toString();
      return 'Server error ${e.response?.statusCode}';
    }
    return 'Network error: ${e.message}';
  }
}