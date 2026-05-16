// lib/screens/profile_screen.dart
// User profile screen — edit name/bio, view study history, stats summary.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import 'results_screen.dart';
import '../main.dart' show slideRoute;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _auth    = AuthService();
  final _profile = ProfileService();
  late TabController _tabs;

  UserProfile?                   _userProfile;
  List<Map<String, dynamic>>     _history = [];
  bool    _loadingProfile = true;
  bool    _loadingHistory = true;
  String? _error;

  // Edit mode
  bool _editing = false;
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  bool _saving    = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _auth.userId;
    if (uid == null) return;

    // Load profile
    try {
      final p = await _profile.getProfile(uid);
      if (mounted) {
        setState(() {
          _userProfile    = p;
          _loadingProfile = false;
          _nameCtrl.text  = p.fullName;
          _bioCtrl.text   = p.bio;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString(); _loadingProfile = false; });
    }

    // Load history
    try {
      final h = await _profile.getUserHistory(uid);
      if (mounted) setState(() { _history = h; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _saveProfile() async {
    final uid = _auth.userId;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final updated = await _profile.updateProfile(
        uid,
        fullName: _nameCtrl.text.trim(),
        bio:      _bioCtrl.text.trim(),
      );
      if (mounted) setState(() {
        _userProfile = updated;
        _editing     = false;
        _saving      = false;
      });
      if (mounted) _showSnack('Profile updated ✅');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      if (mounted) _showSnack('Failed: $e', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.accentRed : AppColors.accentGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading:  BackButton(color: AppColors.textSecond),
        title:    Text('My Profile', style: AppText.subheading),
        actions: [
          if (!_editing && _userProfile != null)
            IconButton(
              icon:    const Icon(Icons.edit_rounded,
                  color: AppColors.primary, size: 20),
              onPressed: () => setState(() => _editing = true),
              tooltip:   'Edit profile',
            ),
          if (_editing) ...[
            TextButton(
              onPressed: _saving ? null : _saveProfile,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2))
                  : Text('Save',
                      style: AppText.body.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => setState(() {
                _editing       = false;
                _nameCtrl.text = _userProfile?.fullName ?? '';
                _bioCtrl.text  = _userProfile?.bio ?? '';
              }),
              child: Text('Cancel', style: AppText.body
                  .copyWith(color: AppColors.textSecond)),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller:          _tabs,
                dividerColor:        Colors.transparent,
                indicator: BoxDecoration(
                  gradient:     AppColors.primaryGrad,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [BoxShadow(
                      color: AppColors.primaryGlow, blurRadius: 8)]),
                labelStyle:          AppText.label.copyWith(color: Colors.white),
                unselectedLabelStyle: AppText.label,
                tabs: const [
                  Tab(text: 'Profile'),
                  Tab(text: 'History'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: _loadingProfile
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2.5))
            : _error != null
                ? _buildError()
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildProfileTab(),
                      _buildHistoryTab(),
                    ],
                  ),
      ),
    );
  }

  // ── Profile tab ───────────────────────────────────────────────────────────
  Widget _buildProfileTab() {
    final p = _userProfile!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [

        // ── Avatar + name ──────────────────────────────────────────────────
        Container(
          padding:     const EdgeInsets.all(24),
          decoration:  cardDecoration(),
          child: Column(children: [
            // Avatar circle
            Container(
              width:  80, height: 80,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, gradient: AppColors.primaryGrad),
              child: Center(child: Text(p.initials,
                  style: AppText.display(28).copyWith(color: Colors.white))),
            ),
            const SizedBox(height: 16),

            if (_editing) ...[
              // Edit fields
              TextFormField(
                controller: _nameCtrl,
                style:      AppText.body,
                decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline,
                        color: AppColors.textMuted, size: 20)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bioCtrl,
                style:      AppText.body,
                maxLines:   3,
                decoration: const InputDecoration(
                    labelText: 'Bio',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded,
                        color: AppColors.textMuted, size: 20)),
              ),
            ] else ...[
              // Display fields
              Text(p.fullName.isNotEmpty ? p.fullName : 'No name set',
                  style: AppText.subheading),
              const SizedBox(height: 4),
              Text(p.email, style: AppText.caption),
              if (p.bio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(p.bio, style: AppText.caption,
                    textAlign: TextAlign.center),
              ],
              if (p.isAdmin) ...[
                const SizedBox(height: 12),
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
                    Text('Admin',
                        style: AppText.label.copyWith(
                            color: AppColors.accentAmber)),
                  ]),
                ),
              ],
            ],
          ]),
        ).animate().fadeIn().slideY(begin: 0.1),

        const SizedBox(height: 16),

        // ── Stats cards ────────────────────────────────────────────────────
        Row(children: [
          _MiniStat(
            label: 'Sessions',
            value: '${_history.length}',
            icon:  Icons.description_rounded,
            color: AppColors.accentBlue,
          ),
          const SizedBox(width: 10),
          _MiniStat(
            label: 'Member since',
            value: _formatDate(p.createdAt),
            icon:  Icons.calendar_today_rounded,
            color: AppColors.accentGreen,
          ),
        ]).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

        const SizedBox(height: 16),

        // ── Account info card ──────────────────────────────────────────────
        Container(
          padding:    const EdgeInsets.all(18),
          decoration: cardDecoration(),
          child: Column(children: [
            _InfoRow(icon: Icons.email_outlined,
                label: 'Email', value: p.email),
            const Divider(color: AppColors.borderLight, height: 20),
            _InfoRow(icon: Icons.fingerprint_rounded,
                label: 'User ID',
                value: p.id.substring(0, 8) + '…'),
            const Divider(color: AppColors.borderLight, height: 20),
            _InfoRow(icon: Icons.admin_panel_settings_rounded,
                label: 'Role',
                value: p.isAdmin ? 'Administrator' : 'Student'),
          ]),
        ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),
      ]),
    );
  }

  // ── History tab ───────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator(
          color: AppColors.primary, strokeWidth: 2.5));
    }
    if (_history.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.history_rounded, size: 52, color: AppColors.textMuted),
        const SizedBox(height: 14),
        Text('No study sessions yet', style: AppText.body),
        const SizedBox(height: 4),
        Text('Upload a document to get started', style: AppText.caption),
      ]));
    }

    return ListView.builder(
      padding:     const EdgeInsets.all(16),
      itemCount:   _history.length,
      itemBuilder: (ctx, i) {
        final s       = _history[i];
        final id      = s['id'] as String? ?? '';
        final summary = (s['summary'] as String? ?? '')
            .replaceAll('__pending__', 'Processing…');
        final date    = _formatDate(s['created_at'] as String? ?? '');

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
              slideRoute(ResultsScreen(resultId: id))),
          child: Container(
            margin:     const EdgeInsets.only(bottom: 10),
            padding:    const EdgeInsets.all(16),
            decoration: cardDecoration(),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient:     AppColors.primaryGrad,
                  borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text('${i + 1}',
                      style: AppText.body.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Session #${i + 1}',
                    style: AppText.bodySmall.copyWith(
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(summary,
                    maxLines:  2,
                    overflow:  TextOverflow.ellipsis,
                    style:     AppText.caption),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time_rounded,
                      size: 11, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(date, style: AppText.label
                      .copyWith(color: AppColors.textMuted, fontSize: 10)),
                ]),
              ])),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textMuted),
            ]),
          ),
        ).animate().fadeIn(delay: (i * 50).ms).slideX(begin: 0.06);
      },
    );
  }

  Widget _buildError() => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline_rounded,
        size: 48, color: AppColors.accentRed),
    const SizedBox(height: 14),
    Text('Failed to load profile', style: AppText.subheading),
    const SizedBox(height: 6),
    Text(_error!, style: AppText.caption, textAlign: TextAlign.center),
    const SizedBox(height: 20),
    ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry')),
  ]));

  String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return iso.substring(0, 10); }
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStat({required this.label, required this.value,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: color.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 8),
        Text(value, style: AppText.subheading.copyWith(color: color)),
        Text(label, style: AppText.label.copyWith(
            color: color.withOpacity(0.7))),
      ]),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: AppColors.textMuted, size: 18),
    const SizedBox(width: 12),
    Text(label, style: AppText.caption),
    const Spacer(),
    Text(value, style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600)),
  ]);
}
