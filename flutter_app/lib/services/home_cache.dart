// lib/services/home_cache.dart
// In-memory cache for HomeScreen data.
// Serves stale data instantly on return, then background-refreshes.
//
// CHANGES FROM ORIGINAL:
//   1. Added _ownerUserId stamp — cache is only valid for the user who
//      populated it. Cross-user hits are impossible even if invalidate()
//      is never called.
//   2. updateSessions() now stamps _ownerUserId from AuthService.userId.
//   3. hasData now also checks _ownerUserId == AuthService.userId.
//   4. invalidate() also clears _ownerUserId for safety.

import '../models/study_result.dart';
import '../models/profile.dart';
import 'auth_service.dart';

class HomeCache {
  HomeCache._();
  static final HomeCache instance = HomeCache._();

  // ── Owner stamp ─────────────────────────────────────────────────────────────
  // Tracks which user's data is currently cached.
  // If the signed-in user changes, hasData returns false automatically.
  String _ownerUserId = '';

  // ── Cached data ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>>? sessions;
  List<StudyResult>?          parsed;
  UserProfile?                profile;

  int    questionsThisWeek  = 0;
  int    flashcardsThisWeek = 0;
  int    questionsDelta     = 0;
  int    flashcardsDelta    = 0;
  double accuracyRate       = 0.0;
  int    unreadCount        = 0;

  DateTime? lastFetched;

  // ── State ───────────────────────────────────────────────────────────────────

  /// True only when:
  ///   • sessions have been written, AND
  ///   • a fetch timestamp exists, AND
  ///   • the cached data belongs to the currently signed-in user.
  bool get hasData =>
      sessions != null &&
          lastFetched != null &&
          _ownerUserId.isNotEmpty &&
          _ownerUserId == AuthService.userId;

  /// Returns true if the cache is older than [maxAge].
  bool isStale({Duration maxAge = const Duration(minutes: 3)}) {
    if (lastFetched == null) return true;
    return DateTime.now().difference(lastFetched!) > maxAge;
  }

  // ── Invalidate ──────────────────────────────────────────────────────────────
  /// Call after any mutation (upload, delete, rename, sign-out) to force
  /// a full refresh. Also clears the owner stamp so hasData returns false
  /// even before a new user signs in.
  void invalidate() {
    lastFetched   = null;
    _ownerUserId  = '';
  }

  // ── Write ───────────────────────────────────────────────────────────────────

  /// Stores sessions and stamps the cache with the current user's ID.
  /// Must be called after AuthService has written the new user's ID
  /// (i.e. after sign-in / sign-up completes).
  void updateSessions(
      List<Map<String, dynamic>> s, List<StudyResult> p) {
    sessions     = List.from(s);
    parsed       = List.from(p);
    _ownerUserId = AuthService.userId; // stamp with current user
  }

  void updateProfile(UserProfile? p) {
    profile = p;
  }

  void updateStats({
    required int    questionsThisWeek,
    required int    flashcardsThisWeek,
    required int    questionsDelta,
    required int    flashcardsDelta,
    required double accuracyRate,
  }) {
    this.questionsThisWeek  = questionsThisWeek;
    this.flashcardsThisWeek = flashcardsThisWeek;
    this.questionsDelta     = questionsDelta;
    this.flashcardsDelta    = flashcardsDelta;
    this.accuracyRate       = accuracyRate;
  }

  void updateUnread(int count) {
    unreadCount = count;
  }

  void markFetched() {
    lastFetched = DateTime.now();
  }
}