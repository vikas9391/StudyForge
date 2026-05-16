// lib/models/profile.dart
// Data models for user profiles and admin views.

class UserProfile {
  final String  id;
  final String  email;
  final String  fullName;
  final String  bio;
  final String  avatarUrl;
  final bool    isAdmin;
  final String  createdAt;
  final int     sessionCount;

  UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.bio,
    required this.avatarUrl,
    required this.isAdmin,
    required this.createdAt,
    this.sessionCount = 0,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id:           j['id']           as String?  ?? '',
    email:        j['email']        as String?  ?? '',
    fullName:     j['full_name']    as String?  ?? '',
    bio:          j['bio']          as String?  ?? '',
    avatarUrl:    j['avatar_url']   as String?  ?? '',
    isAdmin:      j['is_admin']     as bool?    ?? false,
    createdAt:    j['created_at']   as String?  ?? '',
    sessionCount: j['session_count'] as int?    ?? 0,
  );

  // Returns initials for avatar placeholder
  String get initials {
    if (fullName.isNotEmpty) {
      final parts = fullName.trim().split(' ');
      return parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : fullName[0].toUpperCase();
    }
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }
}

class AdminStats {
  final int    totalUsers;
  final int    totalSessions;
  final int    sessionsToday;
  final List<Map<String, dynamic>> recentSignups;

  AdminStats({
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
}
