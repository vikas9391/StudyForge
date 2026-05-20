// lib/models/profile.dart
// Data models for user profiles and admin views.

class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final String phone;
  final String bio;
  final String avatarUrl;
  final bool   isAdmin;
  final String createdAt;
  final int    sessionCount;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.bio,
    required this.avatarUrl,
    required this.isAdmin,
    required this.createdAt,
    this.sessionCount = 0,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id:           j['id']            as String? ?? '',
    email:        j['email']         as String? ?? '',
    fullName:     j['full_name']     as String? ?? '',
    phone:        j['phone']         as String? ?? '',
    bio:          j['bio']           as String? ?? '',
    avatarUrl:    j['avatar_url']    as String? ?? '',
    isAdmin:      j['is_admin']      as bool?   ?? false,
    createdAt:    j['created_at']    as String? ?? '',
    sessionCount: j['session_count'] as int?    ?? 0,
  );

  /// Initials for the avatar circle — up to 2 characters.
  /// Handles extra whitespace, single-word names, and empty names gracefully.
  String get initials {
    final name = fullName.trim();
    if (name.isEmpty) {
      return email.isNotEmpty ? email[0].toUpperCase() : '?';
    }
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }

  UserProfile copyWith({
    String? fullName,
    String? phone,
    String? bio,
    String? avatarUrl,
    int?    sessionCount,
  }) => UserProfile(
    id:           id,
    email:        email,
    fullName:     fullName     ?? this.fullName,
    phone:        phone        ?? this.phone,
    bio:          bio          ?? this.bio,
    avatarUrl:    avatarUrl    ?? this.avatarUrl,
    isAdmin:      isAdmin,
    createdAt:    createdAt,
    sessionCount: sessionCount ?? this.sessionCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is UserProfile &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'UserProfile(id: $id, email: $email, '
      'fullName: $fullName, isAdmin: $isAdmin, sessionCount: $sessionCount)';
}

// ── Admin models ──────────────────────────────────────────────────────────────

class AdminStats {
  final int                        totalUsers;
  final int                        totalSessions;
  final int                        sessionsToday;
  final List<Map<String, dynamic>> recentSignups;

  const AdminStats({
    required this.totalUsers,
    required this.totalSessions,
    required this.sessionsToday,
    required this.recentSignups,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
    totalUsers:    j['total_users']    as int? ?? 0,
    totalSessions: j['total_sessions'] as int? ?? 0,
    sessionsToday: j['sessions_today'] as int? ?? 0,
    recentSignups: List<Map<String, dynamic>>.from(
        j['recent_signups'] as List? ?? []),
  );

  @override
  String toString() => 'AdminStats(totalUsers: $totalUsers, '
      'totalSessions: $totalSessions, sessionsToday: $sessionsToday)';
}