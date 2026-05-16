// lib/screens/admin/admin_users_screen.dart
// Paginated list of all users with search, session count, and actions.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';
import '../../models/profile.dart';
import '../../services/profile_service.dart';
import 'admin_user_detail_screen.dart';
import '../../main.dart' show slideRoute;

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _profileSvc   = ProfileService();
  final _searchCtrl   = TextEditingController();

  List<UserProfile> _users      = [];
  List<UserProfile> _filtered   = [];
  bool    _loading              = true;
  int     _total                = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _profileSvc.getAdminUsers(limit: 100);
      final raw  = data['users'] as List? ?? [];
      final list = raw
          .map((u) => UserProfile.fromJson(u as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() {
        _users    = list;
        _filtered = list;
        _total    = data['total'] as int? ?? list.length;
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _filterUsers() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _users
          : _users.where((u) =>
              u.email.toLowerCase().contains(q) ||
              u.fullName.toLowerCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading:  BackButton(color: AppColors.textSecond),
        title:    Text('All Users ($_total)', style: AppText.subheading),
        actions: [
          IconButton(
            icon:     const Icon(Icons.refresh_rounded,
                color: AppColors.textSecond),
            onPressed: _load,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: Column(children: [

          // ── Search bar ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller:  _searchCtrl,
              style:       AppText.body,
              decoration:  InputDecoration(
                hintText:    'Search by email or name…',
                prefixIcon:  const Icon(Icons.search_rounded,
                    color: AppColors.textMuted, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.textMuted, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _filterUsers();
                        })
                    : null,
              ),
            ),
          ),

          // ── User list ──────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2.5))
                : _error != null
                    ? _buildError()
                    : _filtered.isEmpty
                        ? Center(child: Text('No users found.',
                            style: AppText.caption))
                        : RefreshIndicator(
                            onRefresh: _load,
                            color:     AppColors.primary,
                            child: ListView.builder(
                              padding:     const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount:   _filtered.length,
                              itemBuilder: (ctx, i) =>
                                  _buildUserTile(_filtered[i], i),
                            ),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _buildUserTile(UserProfile u, int i) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
          slideRoute(AdminUserDetailScreen(userId: u.id))),
      child: Container(
        margin:     const EdgeInsets.only(bottom: 10),
        padding:    const EdgeInsets.all(14),
        decoration: cardDecoration(),
        child: Row(children: [

          // Avatar
          Container(
            width:  44, height: 44,
            decoration: BoxDecoration(
              gradient:     u.isAdmin
                  ? const LinearGradient(
                      colors: [AppColors.accentAmber, Color(0xFFE67E00)])
                  : AppColors.primaryGrad,
              borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(u.initials,
                style: AppText.body.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700))),
          ),

          const SizedBox(width: 14),

          // Info
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  u.fullName.isNotEmpty ? u.fullName : u.email,
                  style: AppText.bodySmall
                      .copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (u.isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:        AppColors.accentAmber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text('Admin',
                      style: AppText.label.copyWith(
                          color: AppColors.accentAmber, fontSize: 9)),
                ),
            ]),
            const SizedBox(height: 3),
            Text(u.fullName.isNotEmpty ? u.email : '',
                style: AppText.caption,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Row(children: [
              const Icon(Icons.description_rounded,
                  size: 11, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text('${u.sessionCount} sessions',
                  style: AppText.label.copyWith(
                      color: AppColors.textMuted, fontSize: 10)),
              const SizedBox(width: 12),
              const Icon(Icons.access_time_rounded,
                  size: 11, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(_fmtDate(u.createdAt),
                  style: AppText.label.copyWith(
                      color: AppColors.textMuted, fontSize: 10)),
            ]),
          ])),

          const Icon(Icons.chevron_right_rounded,
              size: 16, color: AppColors.textMuted),
        ]),
      ),
    ).animate().fadeIn(delay: (i * 40).ms).slideX(begin: 0.06);
  }

  Widget _buildError() => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline_rounded,
        size: 48, color: AppColors.accentRed),
    const SizedBox(height: 14),
    Text('Failed to load users', style: AppText.subheading),
    const SizedBox(height: 6),
    Text(_error!, style: AppText.caption, textAlign: TextAlign.center),
    const SizedBox(height: 20),
    ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry')),
  ]));

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return iso.length >= 10 ? iso.substring(0, 10) : iso; }
  }
}
