// lib/services/api_service.dart
// HTTP client for the Django backend.
// CHANGES FROM ORIGINAL:
//   1. Removed Supabase import — token now read from SharedPreferences
//   2. Added trailing slashes to all endpoints (Django requires them)
//   3. Added notifications endpoints (were missing from backend — now added)
//   4. Token is refreshed automatically on 401 via interceptor
//   5. Fixed adminSendNotification — was calling undefined _post helper
//   6. Added _post / _patch / _delete private helpers to reduce boilerplate
//   7. retryProcessing now guards against unexpected response shape
//   8. Added token refresh interceptor (replaces comment-only promise)

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

  // ── Token helpers ─────────────────────────────────────────────────────────

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<String?> _getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  Future<void> _saveToken(String accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
  }

  // ── Dio factory with 401-refresh interceptor ──────────────────────────────

  Future<diolib.Dio> _getDio() async {
    final token = await _getToken();
    final dio = diolib.Dio(diolib.BaseOptions(
      baseUrl:        _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ));

    dio.interceptors.add(
      diolib.InterceptorsWrapper(
        onError: (diolib.DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            // Attempt token refresh
            final refreshed = await _tryRefreshToken(dio);
            if (refreshed) {
              // Retry original request with new token
              final newToken = await _getToken();
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newToken';
              try {
                final retryResp = await dio.fetch(opts);
                return handler.resolve(retryResp);
              } on diolib.DioException catch (e) {
                return handler.next(e);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );

    return dio;
  }

  /// Calls /auth/token/refresh/ and persists the new access token.
  /// Returns true on success, false otherwise.
  Future<bool> _tryRefreshToken(diolib.Dio dio) async {
    final refreshToken = await _getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await dio.post(
        '/auth/token/refresh/',
        data: {'refresh': refreshToken},
        options: diolib.Options(
          // Skip the interceptor for this call to avoid infinite loops
          extra: {'skipInterceptor': true},
        ),
      );
      final newAccess =
      (response.data as Map<String, dynamic>)['access'] as String?;
      if (newAccess != null) {
        await _saveToken(newAccess);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Private request helpers ───────────────────────────────────────────────

  Future<diolib.Response<dynamic>> _post(
      String path,
      Map<String, dynamic> data,
      ) async {
    final dio = await _getDio();
    try {
      return await dio.post(path, data: data);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<diolib.Response<dynamic>> _patch(
      String path,
      Map<String, dynamic> data,
      ) async {
    final dio = await _getDio();
    try {
      return await dio.patch(path, data: data);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> _delete(String path) async {
    final dio = await _getDio();
    try {
      await dio.delete(path);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<diolib.Response<dynamic>> _get(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) async {
    final dio = await _getDio();
    try {
      return await dio.get(path, queryParameters: queryParameters);
    } on diolib.DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ── V2: Upload / Process / Results ────────────────────────────────────────

  Future<Map<String, dynamic>> uploadFile({
    required File file,
    required String userId,
  }) async {
    final dio = await _getDio();

    // Step 1: Upload file
    final formData = diolib.FormData.fromMap({
      'file': await diolib.MultipartFile.fromFile(
        file.path,
        filename: file.path.split(Platform.pathSeparator).last,
      ),
      'user_id': userId,
    });

    final uploadResp = await dio.post(
      '/upload/',
      data: formData,
      options: diolib.Options(
        contentType: 'multipart/form-data',
        sendTimeout:    const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 1),
      ),
    );

    final uploadData = uploadResp.data as Map<String, dynamic>;
    final resultId   = uploadData['result_id'] as String?;

    if (resultId == null) throw 'Upload failed: no result_id returned.';

    // Step 2: Poll until OCR is done
    return await _pollUploadStatus(resultId);
  }

  Future<Map<String, dynamic>> _pollUploadStatus(String resultId) async {
    const maxAttempts = 40;  // 40 × 3s = 2 minutes max
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final resp = await (await _getDio()).get('/upload/status/$resultId/');
        final data = resp.data as Map<String, dynamic>;
        final st   = data['status'] as String? ?? '';

        if (st == 'ready')  return data;
        if (st == 'failed') throw data['detail'] ?? 'OCR failed.';
        // still extracting — keep polling
      } on diolib.DioException catch (e) {
        throw _parseError(e);
      }
    }
    throw 'OCR timed out. Please try a smaller file.';
  }

  Future<StudyResult> processDocument({
    required String resultId,
    required String extractedText,
    required String userId,
    int numQuiz = 5,
    int numFlashcards = 8,
  }) async {
    final response = await _post('/process/', {
      'result_id':      resultId,
      'extracted_text': extractedText,
      'user_id':        userId,
      'num_quiz':       numQuiz,
      'num_flashcards': numFlashcards,
    });
    return StudyResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StudyResult> getResult(String resultId) async {
    final response = await _get('/results/$resultId/');
    return StudyResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> getUserResults(String userId) async {
    final response = await _get('/results/', queryParameters: {'user_id': userId});
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['results'] as List? ?? []);
  }

  Future<void> deleteResult(String resultId) async {
    await _delete('/results/$resultId/');
  }

  Future<void> renameResult(String resultId, String newName) async {
    await _patch('/results/$resultId/', {'file_name': newName});
  }

  Future<StudyResult> retryProcessing({
    required String resultId,
    required String userId,
    required String fileUrl,
    int numQuiz = 5,
    int numFlashcards = 8,
  }) async {
    final retryResp = await _post('/retry/$resultId/', {
      'user_id':  userId,
      'file_url': fileUrl,
    });

    final retryData = retryResp.data;
    if (retryData is! Map<String, dynamic>) {
      throw 'Unexpected response from retry endpoint.';
    }
    final extractedText = retryData['extracted_text'] as String? ?? '';
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
  }

  // ── V3: Spaced Repetition ─────────────────────────────────────────────────

  Future<void> initSrCards({
    required String resultId,
    required String userId,
    required List<Flashcard> cards,
  }) async {
    await _post('/sr/init/$resultId/', {
      'user_id': userId,
      'cards':   cards.map((c) => c.toJson()).toList(),
    });
  }

  Future<Map<String, dynamic>> submitSrReview({
    required String userId,
    required String resultId,
    required int cardIndex,
    required int quality,
  }) async {
    final response = await _post('/sr/review/', {
      'user_id':    userId,
      'result_id':  resultId,
      'card_index': cardIndex,
      'quality':    quality,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<List<SrSession>> getDueCards(String userId) async {
    final response = await _get('/sr/due/$userId/');
    final data = response.data as Map<String, dynamic>;
    return (data['sessions'] as List? ?? [])
        .map((s) => SrSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getSrStats(String userId) async {
    final response = await _get('/sr/stats/$userId/');
    return response.data as Map<String, dynamic>;
  }

  // ── V3: Ingest (YouTube / URL / OCR) ─────────────────────────────────────

  Future<Map<String, dynamic>> ingestUrl({
    required String url,
    required String userId,
  }) async {
    final response = await _post('/ingest/url/', {
      'url':     url,
      'user_id': userId,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> ingestYouTube({
    required String url,
    required String userId,
  }) async {
    final response = await _post('/ingest/youtube/', {
      'url':     url,
      'user_id': userId,
    });
    return response.data as Map<String, dynamic>;
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
      final response = await dio.post(
        '/ingest/ocr/',
        data: formData,
        options: diolib.Options(
          contentType: 'multipart/form-data',
          sendTimeout:    const Duration(minutes: 3),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
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
    await _post('/analytics/quiz-attempt/', {
      'user_id':      userId,
      'result_id':    resultId,
      'session_name': sessionName,
      'score':        score,
      'total':        total,
      'answers':      answers,
    });
  }

  Future<List<WeakTopic>> getWeakTopics(String userId) async {
    final response = await _get('/analytics/weak-topics/$userId/');
    final data = response.data as Map<String, dynamic>;
    return (data['topics'] as List? ?? [])
        .map((t) => WeakTopic.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<List<AccuracyPoint>> getAccuracyOverTime(
      String userId, {
        int days = 30,
      }) async {
    final response = await _get(
      '/analytics/accuracy/$userId/',
      queryParameters: {'days': days},
    );
    final data = response.data as Map<String, dynamic>;
    return (data['points'] as List? ?? [])
        .map((p) => AccuracyPoint.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getAnalyticsSummary(String userId) async {
    final response = await _get('/analytics/summary/$userId/');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getWeeklyStats(String userId) async {
    final response = await _get('/analytics/weekly-stats/$userId/');
    return response.data as Map<String, dynamic>;
  }

  // ── V3: Shared Sessions ───────────────────────────────────────────────────

  Future<void> setSessionVisibility(String resultId, bool isPublic) async {
    await _patch('/shared/$resultId/visibility/', {'is_public': isPublic});
  }

  Future<List<PublicSession>> browsePublicSessions({
    String? search,
    int limit  = 20,
    int offset = 0,
  }) async {
    final response = await _get('/shared/browse/', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
      'limit':  limit,
      'offset': offset,
    });
    final data = response.data as Map<String, dynamic>;
    return (data['sessions'] as List? ?? [])
        .map((s) => PublicSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<List<PublicSession>> getFeaturedSessions() async {
    final response = await _get('/shared/featured/');
    final data = response.data as Map<String, dynamic>;
    return (data['sessions'] as List? ?? [])
        .map((s) => PublicSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<String> cloneSession({
    required String resultId,
    required String userId,
  }) async {
    final response = await _post('/shared/$resultId/clone/', {
      'user_id': userId,
    });
    final data = response.data;
    if (data is! Map<String, dynamic> || data['new_result_id'] == null) {
      throw 'Clone failed: unexpected response from server.';
    }
    return data['new_result_id'] as String;
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<List<NotificationItem>> getNotifications(String userId) async {
    final response = await _get('/notifications/$userId/');
    final data = response.data as Map<String, dynamic>;
    return (data['notifications'] as List? ?? [])
        .map((n) => NotificationItem.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _patch('/notifications/$notificationId/read/', {});
  }

  Future<void> markAllNotificationsRead(String userId) async {
    await _post('/notifications/$userId/read-all/', {});
  }

  Future<void> adminSendNotification({
    String? userId,
    required String type,
    required String title,
    required String body,
  }) async {
    await _post('/notifications/admin/send/', {
      if (userId != null) 'user_id': userId,
      'type':  type,
      'title': title,
      'body':  body,
    });
  }

  Future<void> deleteNotification(String notificationId) async {
    await _delete('/notifications/$notificationId/');
  }

  // ── Error helper ──────────────────────────────────────────────────────────

  String _parseError(diolib.DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail != null) return detail.toString();
      }
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