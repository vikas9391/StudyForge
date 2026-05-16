// lib/services/api_service.dart
// HTTP client for the FastAPI backend.
//
// FIX: supabase_flutter transitively imports package:http which also exports
// MultipartFile. We import dio with a prefix 'diolib' so the compiler never
// gets confused between dio.MultipartFile and http.MultipartFile.

import 'dart:io';
import 'package:dio/dio.dart' as diolib;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/study_result.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  String? get _token =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  diolib.Dio get _dio => diolib.Dio(diolib.BaseOptions(
    baseUrl:        _baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
    headers: {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    },
  ));

  // ── Upload File ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> uploadFile({
    required File   file,
    required String userId,
  }) async {
    try {
      final formData = diolib.FormData.fromMap({
        'file': await diolib.MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
        'user_id': userId,
      });
      final response = await _dio.post(
        '/upload/',
        data:    formData,
        options: diolib.Options(contentType: 'multipart/form-data'),
      );
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── Process Document ─────────────────────────────────────────────────────
  Future<StudyResult> processDocument({
    required String resultId,
    required String extractedText,
    required String userId,
    int numQuiz       = 5,
    int numFlashcards = 8,
  }) async {
    try {
      final response = await _dio.post('/process/', data: {
        'result_id':      resultId,
        'extracted_text': extractedText,
        'user_id':        userId,
        'num_quiz':       numQuiz,
        'num_flashcards': numFlashcards,
      });
      return StudyResult.fromJson(response.data as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── Get Single Result ────────────────────────────────────────────────────
  Future<StudyResult> getResult(String resultId) async {
    try {
      final response = await _dio.get('/results/$resultId');
      return StudyResult.fromJson(response.data as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── Get All Results for User ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getUserResults(String userId) async {
    try {
      final response = await _dio.get(
        '/results/',
        queryParameters: {'user_id': userId},
      );
      final data = response.data as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['results'] as List? ?? []);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── Error helper ─────────────────────────────────────────────────────────
  String _parseError(diolib.DioException e) {
    if (e.response != null) {
      final detail = (e.response?.data as Map?)?['detail'];
      if (detail != null) return detail.toString();
      return 'Server error ${e.response?.statusCode}';
    }
    if (e.type == diolib.DioExceptionType.connectionTimeout ||
        e.type == diolib.DioExceptionType.receiveTimeout) {
      return 'Request timed out. AI models can be slow — please retry.';
    }
    return 'Network error: ${e.message}';
  }
}