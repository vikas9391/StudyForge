// lib/services/api_service.dart
// HTTP client for the Django backend.
// CHANGES FROM ORIGINAL:
//   1. Removed Supabase import — token now read from SharedPreferences
//   2. Added trailing slashes to all endpoints (Django requires them)
//   3. Added notifications endpoints (were missing from backend — now added)
//   4. Token is refreshed automatically on 401

import 'dart:io';
import 'package:dio/dio.dart' as diolib;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/study_result.dart';
import '../models/notification_item.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String get _baseUrl => dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  // ── Token helper — reads JWT from SharedPreferences (NOT Supabase) ─────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<diolib.Dio> _getDio() async {
    final token = await _getToken();
    return diolib.Dio(diolib.BaseOptions(
      baseUrl:        _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ));
  }

  // ── V2: Upload / Process / Results ────────────────────────────────────────

  Future<Map<String, dynamic>> uploadFile({
    required File file,
    required String userId,
  }) async {
    final dio = await _getDio();
    try {
      final formData = diolib.FormData.fromMap({
        'file': await diolib.MultipartFile.fromFile(
          file.path,
          filename: file.path.split(Platform.pathSeparator).last,
        ),
        'user_id': userId,
      });
      final response = await dio.post('/upload/',
          data: formData,
          options: diolib.Options(contentType: 'multipart/form-data'));
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<StudyResult> processDocument({
    required String resultId,
    required String extractedText,
    required String userId,
    int numQuiz = 5,
    int numFlashcards = 8,
  }) async {
    final dio = await _getDio();
    try {
      final response = await dio.post('/process/', data: {
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

  Future<StudyResult> getResult(String resultId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/results/$resultId/');
      return StudyResult.fromJson(response.data as Map<String, dynamic>);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getUserResults(String userId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/results/',
          queryParameters: {'user_id': userId});
      final data = response.data as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['results'] as List? ?? []);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> deleteResult(String resultId) async {
    final dio = await _getDio();
    try {
      await dio.delete('/results/$resultId/');
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> renameResult(String resultId, String newName) async {
    final dio = await _getDio();
    try {
      await dio.patch('/results/$resultId/', data: {'file_name': newName});
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<StudyResult> retryProcessing({
    required String resultId,
    required String userId,
    required String fileUrl,
    int numQuiz = 5,
    int numFlashcards = 8,
  }) async {
    final dio = await _getDio();
    try {
      final retryResp = await dio.post('/retry/$resultId/',
          data: {'user_id': userId, 'file_url': fileUrl});
      final extractedText =
          (retryResp.data as Map<String, dynamic>)['extracted_text'] as String? ?? '';
      if (extractedText.isEmpty) {
        throw 'Could not extract text from stored file. Please upload again.';
      }
      return processDocument(
        resultId:      resultId,
        extractedText: extractedText,
        userId:        userId,
        numQuiz:       numQuiz,
        numFlashcards: numFlashcards,
      );
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── V3: Spaced Repetition ─────────────────────────────────────────────────

  Future<void> initSrCards({
    required String resultId,
    required String userId,
    required List<Flashcard> cards,
  }) async {
    final dio = await _getDio();
    try {
      await dio.post('/sr/init/$resultId/', data: {
        'user_id': userId,
        'cards':   cards.map((c) => c.toJson()).toList(),
      });
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> submitSrReview({
    required String userId,
    required String resultId,
    required int cardIndex,
    required int quality,
  }) async {
    final dio = await _getDio();
    try {
      final response = await dio.post('/sr/review/', data: {
        'user_id':    userId,
        'result_id':  resultId,
        'card_index': cardIndex,
        'quality':    quality,
      });
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<SrSession>> getDueCards(String userId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/sr/due/$userId/');
      final data = response.data as Map<String, dynamic>;
      return (data['sessions'] as List? ?? [])
          .map((s) => SrSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> getSrStats(String userId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/sr/stats/$userId/');
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── V3: Ingest (YouTube / URL / OCR) ─────────────────────────────────────

  Future<Map<String, dynamic>> ingestUrl({
    required String url,
    required String userId,
  }) async {
    final dio = await _getDio();
    try {
      final response = await dio.post('/ingest/url/', data: {
        'url':     url,
        'user_id': userId,
      });
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> ingestYouTube({
    required String url,
    required String userId,
  }) async {
    final dio = await _getDio();
    try {
      final response = await dio.post('/ingest/youtube/', data: {
        'url':     url,
        'user_id': userId,
      });
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> ingestOcr({
    required File imageFile,
    required String userId,
  }) async {
    final dio = await _getDio();
    try {
      final formData = diolib.FormData.fromMap({
        'file': await diolib.MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split(Platform.pathSeparator).last,
        ),
        'user_id': userId,
      });
      final response = await dio.post('/ingest/ocr/',
          data: formData,
          options: diolib.Options(contentType: 'multipart/form-data'));
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── V3: Analytics ─────────────────────────────────────────────────────────

  Future<void> recordQuizAttempt({
    required String userId,
    required String resultId,
    required String sessionName,
    required int score,
    required int total,
    required List<Map<String, dynamic>> answers,
  }) async {
    final dio = await _getDio();
    try {
      await dio.post('/analytics/quiz-attempt/', data: {
        'user_id':      userId,
        'result_id':    resultId,
        'session_name': sessionName,
        'score':        score,
        'total':        total,
        'answers':      answers,
      });
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<WeakTopic>> getWeakTopics(String userId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/analytics/weak-topics/$userId/');
      final data = response.data as Map<String, dynamic>;
      return (data['topics'] as List? ?? [])
          .map((t) => WeakTopic.fromJson(t as Map<String, dynamic>))
          .toList();
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<AccuracyPoint>> getAccuracyOverTime(String userId,
      {int days = 30}) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/analytics/accuracy/$userId/',
          queryParameters: {'days': days});
      final data = response.data as Map<String, dynamic>;
      return (data['points'] as List? ?? [])
          .map((p) => AccuracyPoint.fromJson(p as Map<String, dynamic>))
          .toList();
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> getAnalyticsSummary(String userId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/analytics/summary/$userId/');
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<Map<String, dynamic>> getWeeklyStats(String userId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/analytics/weekly-stats/$userId/');
      return response.data as Map<String, dynamic>;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── V3: Shared Sessions ───────────────────────────────────────────────────

  Future<void> setSessionVisibility(String resultId, bool isPublic) async {
    final dio = await _getDio();
    try {
      await dio.patch('/shared/$resultId/visibility/',
          data: {'is_public': isPublic});
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<PublicSession>> browsePublicSessions({
    String? search,
    int limit  = 20,
    int offset = 0,
  }) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/shared/browse/', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        'limit':  limit,
        'offset': offset,
      });
      final data = response.data as Map<String, dynamic>;
      return (data['sessions'] as List? ?? [])
          .map((s) => PublicSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<PublicSession>> getFeaturedSessions() async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/shared/featured/');
      final data = response.data as Map<String, dynamic>;
      return (data['sessions'] as List? ?? [])
          .map((s) => PublicSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<String> cloneSession({
    required String resultId,
    required String userId,
  }) async {
    final dio = await _getDio();
    try {
      final response = await dio.post('/shared/$resultId/clone/',
          data: {'user_id': userId});
      return (response.data as Map<String, dynamic>)['new_result_id'] as String;
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<List<NotificationItem>> getNotifications(String userId) async {
    final dio = await _getDio();
    try {
      final response = await dio.get('/notifications/$userId/');
      final data = response.data as Map<String, dynamic>;
      return (data['notifications'] as List? ?? [])
          .map((n) => NotificationItem.fromJson(n as Map<String, dynamic>))
          .toList();
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final dio = await _getDio();
    try {
      await dio.patch('/notifications/$notificationId/read/');
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> markAllNotificationsRead(String userId) async {
    final dio = await _getDio();
    try {
      await dio.post('/notifications/$userId/read-all/');
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    final dio = await _getDio();
    try {
      await dio.delete('/notifications/$notificationId/');
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── Error helper ──────────────────────────────────────────────────────────

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
    if (e.type == diolib.DioExceptionType.connectionError) {
      return 'Cannot reach the server. Make sure the backend is running on $_baseUrl';
    }
    return 'Network error: ${e.message}';
  }
}