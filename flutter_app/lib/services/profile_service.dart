// lib/services/profile_service.dart
// Handles all profile and admin API calls.
// Uses 'diolib' prefix to avoid MultipartFile conflict with package:http.

import 'package:dio/dio.dart' as diolib;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class ProfileService {
  static final ProfileService _i = ProfileService._();
  factory ProfileService() => _i;
  ProfileService._();

  String get _base => dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';
  String? get _token =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  diolib.Dio get _dio => diolib.Dio(diolib.BaseOptions(
    baseUrl:        _base,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    },
  ));

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<UserProfile> getProfile(String userId) async {
    try {
      final r = await _dio.get('/profile/$userId');
      return UserProfile.fromJson(r.data as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<UserProfile> updateProfile(String userId,
      {String? fullName, String? bio}) async {
    try {
      final body = <String, dynamic>{};
      if (fullName != null) body['full_name'] = fullName;
      if (bio != null)      body['bio']       = bio;

      final r = await _dio.put('/profile/$userId', data: body);
      return UserProfile.fromJson(
          (r.data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<List<Map<String, dynamic>>> getUserHistory(String userId) async {
    try {
      final r = await _dio.get('/profile/$userId/history');
      return List<Map<String, dynamic>>.from(
          (r.data as Map)['sessions'] as List? ?? []);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  // ── Admin ─────────────────────────────────────────────────────────────────

  Future<AdminStats> getAdminStats() async {
    try {
      final r = await _dio.get('/admin/stats');
      return AdminStats.fromJson(r.data as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<Map<String, dynamic>> getAdminUsers(
      {int page = 1, int limit = 20}) async {
    try {
      final r = await _dio.get('/admin/users',
          queryParameters: {'page': page, 'limit': limit});
      return r.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<Map<String, dynamic>> getAdminUserDetail(String userId) async {
    try {
      final r = await _dio.get('/admin/users/$userId');
      return r.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> adminDeleteResult(String resultId) async {
    try {
      await _dio.delete('/admin/results/$resultId');
    } on diolib.DioException catch (e) {
      throw _err(e);
    }
  }

  Future<bool> adminToggleAdmin(String userId) async {
    try {
      final r = await _dio.put('/admin/users/$userId/toggle-admin');
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