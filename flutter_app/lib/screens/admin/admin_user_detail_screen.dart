// lib/screens/admin/admin_user_detail_screen.dart
// Full view of one user: profile info, all sessions, admin actions.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';
import '../../models/profile.dart';
import '../../services/profile_service.dart';
import '../results_screen.dart';
import '../../main.dart' show slideRoute;

class AdminUserDetailScreen extends StatefulWidget {
  final String userId;
  const AdminUserDetailScreen({super.key, required this.userId});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  final _profileSvc = ProfileService();

  UserProfile?               _profile;
  List<Map<String, dynamic>> _sessions = [];
  bool    _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _profileSvc.getAdminUserDetail(widget.userId);
      if (mounted) setState(() {
        _profile  = UserProfile.fromJson(
            data['profile'] as Map<String, dynamic>);
        _sessions = List<Map<String, dynamic>>.from(
            data['sessions'] as List? ?? []);
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggleAdmin() async {
    final p = _profile!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          p.isAdmin ? 'Remove Admin?' : 'Make Admin?',
          style: AppText.subheading,
        ),
        content: Text(
          p.isAdmin
              ? 'This will remove admin privileges from ${p.email}.'
              : 'This will grant admin privileges to ${p.email}.',
          style: AppText.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppText.body
                .copyWith(color: AppColors.textSecond)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: p.isAdmin
                  ? AppColors.accentRed
                  : AppColors.accentAmber),
            child: Text(p.isAdmin ? 'Remove' : 'Grant'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      final newVal = await _profileSvc.adminToggleAdmin(widget.userId);
      if (mounted) {
        setState(() {
          _profile = UserProfile.fromJson({
            ..._profileAsMap(),
            'is_admin': newVal,
          });
        });
        _showSnack(newVal
            ? '${p.email} is now Admin ✅'
            : '${p.email} removed from Admin');
      }
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _deleteSession(String sessionId, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Session?', style: AppText.subheading),
        content: Text('This will permanently remove session #${index + 1}.',
            style: AppText.caption),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppText.body
                .copyWith(color: AppColors.textSecond)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await _profileSvc.adminDeleteResult(sessionId);
      if (mounted) {
        setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
        _showSnack('Session deleted');
      }
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Map<String, dynamic> _profileAsMap() => {
    'id':           _profile!.id,
    'email':        _profile!.email,
    'full_name':    _profile!.fullName,
    'bio':          _profile!.bio,
    'avatar_url':   _profile!.avatarUrl,
    'is_admin':     _profile!.isAdmin,
    'created_at':   _profile!.createdAt,
    'session_count': _sessions.length,
  };

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: error ? AppColors.accentRed : AppColors.accentGreen,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.textSecond),
        title:   Text('User Detail', style: AppText.subheading),
        actions: [
          if (_profile != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textSecond),
              color:       AppColors.surfaceCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'toggle_admin') _toggleAdmin();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle_admin',
                  child: Row(children: [
                    Icon(
                      _profile!.isAdmin
                          ? Icons.remove_moderator_rounded
                          : Icons.shield_rounded,
                      color: _profile!.isAdmin
                          ? AppColors.accentRed
                          : AppColors.accentAmber,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _profile!.isAdmin ? 'Remove Admin' : 'Make Admin',
                      style: AppText.body,
                    ),
                  ]),
                ),
              ],
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2.5))
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final p = _profile!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [

        // ── Profile card ────────────────────────────────────────────────────
        Container(
          padding:    const EdgeInsets.all(20),
          decoration: cardDecoration(),
          child: Column(children: [
            // Avatar
            Container(
              width:  64, height: 64,
              decoration: BoxDecoration(
                gradient:     p.isAdmin
                    ? const LinearGradient(colors: [
                        AppColors.accentAmber, Color(0xFFE67E00)])
                    : AppColors.primaryGrad,
                borderRadius: BorderRadius.circular(18)),
              child: Center(child: Text(p.initials,
                  style: AppText.display(22)
                      .copyWith(color: Colors.white))),
            ),
            const SizedBox(height: 14),
            Text(p.fullName.isNotEmpty ? p.fullName : 'No name',
                style: AppText.subheading),
            const SizedBox(height: 4),
            Text(p.email, style: AppText.caption),
            if (p.isAdmin) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color:        AppColors.accentAmber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.accentAmber.withOpacity(0.4))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.shield_rounded,
                      color: AppColors.accentAmber, size: 14),
                  const SizedBox(width: 5),
                  Text('Administrator',
                      style: AppText.label
                          .copyWith(color: AppColors.accentAmber)),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(color: AppColors.borderLight, height: 1),
            const SizedBox(height: 14),
            // Info rows
            _InfoRow(Icons.fingerprint_rounded, 'User ID',
                p.id.substring(0, 12) + '…'),
            const SizedBox(height: 8),
            _InfoRow(Icons.calendar_today_rounded, 'Joined',
                _fmtDate(p.createdAt)),
            const SizedBox(height: 8),
            _InfoRow(Icons.description_rounded, 'Sessions',
                '${_sessions.length}'),
          ]),
        ).animate().fadeIn().slideY(begin: 0.1),

        const SizedBox(height: 24),

        // ── Sessions ────────────────────────────────────────────────────────
        Row(children: [
          Text('Study Sessions', style: AppText.subheading),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Text('${_sessions.length}',
                style: AppText.label.copyWith(color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 12),

        if (_sessions.isEmpty)
          Container(
            padding:    const EdgeInsets.all(24),
            decoration: cardDecoration(),
            child: Center(child: Text('No sessions yet',
                style: AppText.caption)),
          )
        else
          ..._sessions.asMap().entries.map((e) {
            final i       = e.key;
            final s       = e.value;
            final id      = s['id'] as String? ?? '';
            final summary = (s['summary'] as String? ?? '')
                .replaceAll('__pending__', 'Processing…');
            final date    = _fmtDate(s['created_at'] as String? ?? '');

            return Dismissible(
              key:        Key(id),
              direction:  DismissDirection.endToStart,
              background: Container(
                margin:       const EdgeInsets.only(bottom: 10),
                padding:      const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color:        AppColors.accentRed,
                  borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.centerRight,
                child: const Icon(Icons.delete_rounded, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                await _deleteSession(id, i);
                return false; // we handle list update manually
              },
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                    slideRoute(ResultsScreen(resultId: id))),
                child: Container(
                  margin:     const EdgeInsets.only(bottom: 10),
                  padding:    const EdgeInsets.all(14),
                  decoration: cardDecoration(),
                  child: Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        gradient:     AppColors.primaryGrad,
                        borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text('${i + 1}',
                          style: AppText.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Session #${i + 1}',
                          style: AppText.bodySmall
                              .copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(summary, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption),
                      const SizedBox(height: 3),
                      Text(date, style: AppText.label.copyWith(
                          color: AppColors.textMuted, fontSize: 10)),
                    ])),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: AppColors.textMuted),
                  ]),
                ),
              ),
            ).animate().fadeIn(delay: (i * 40).ms).slideX(begin: 0.06);
          }),

        const SizedBox(height: 12),
        if (_sessions.isNotEmpty)
          Text('← Swipe left on a session to delete',
              style: AppText.label.copyWith(
                  color: AppColors.textMuted),
              textAlign: TextAlign.center),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildError() => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline_rounded,
        size: 48, color: AppColors.accentRed),
    const SizedBox(height: 14),
    Text('Failed to load user', style: AppText.subheading),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: AppColors.textMuted),
    const SizedBox(width: 10),
    Text(label, style: AppText.caption),
    const Spacer(),
    Text(value, style: AppText.bodySmall
        .copyWith(fontWeight: FontWeight.w600)),
  ]);
}
