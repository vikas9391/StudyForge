// lib/screens/profile_screen.dart
// User profile screen — edit name / bio / phone, view study history, stats.
// Restyled to match HomeScreen V3 — warm bg, surface cards, shared nav.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import 'results_screen.dart';
import '../main.dart' show slideRoute;
import '../widgets/app_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _profile = ProfileService();
  late TabController _tabs;

  UserProfile?               _userProfile;
  List<Map<String, dynamic>> _history = [];
  bool    _loadingProfile = true;
  bool    _loadingHistory = true;
  String? _error;

  // Edit mode
  bool _editing = false;
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _bioCtrl   = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;

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
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = AuthService.userId;
    if (uid.isEmpty) return;

    try {
      final p = await _profile.getProfile(uid);
      if (mounted) {
        setState(() {
          _userProfile    = p;
          _loadingProfile = false;
          _nameCtrl.text  = p.fullName;
          _bioCtrl.text   = p.bio;
          _phoneCtrl.text = p.phone;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loadingProfile = false; });
      }
    }

    try {
      final h = await _profile.getUserHistory(uid);
      if (mounted) setState(() { _history = h; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = AuthService.userId;
    if (uid.isEmpty) return;

    setState(() => _saving = true);
    try {
      final updated = await _profile.updateProfile(
        uid,
        fullName: _nameCtrl.text.trim(),
        bio:      _bioCtrl.text.trim(),
        phone:    _phoneCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _userProfile = updated;
          _editing     = false;
          _saving      = false;
        });
        _showSnack('Profile updated ✅');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('Failed: $e', error: true);
      }
    }
  }

  void _cancelEdit() {
    setState(() {
      _editing        = false;
      _nameCtrl.text  = _userProfile?.fullName ?? '';
      _bioCtrl.text   = _userProfile?.bio      ?? '';
      _phoneCtrl.text = _userProfile?.phone    ?? '';
    });
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: TextStyle(color: AppColors.textPrimary)),
      backgroundColor: error ? AppColors.accentRed.withOpacity(0.12) : AppColors.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: error
                ? AppColors.accentRed.withOpacity(0.25)
                : AppColors.border),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EDE8),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                _buildTabBar(),
                Expanded(
                  child: _loadingProfile
                      ? _buildShimmer()
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
              ],
            ),
            // Shared bottom nav
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: AppBottomNav(
                currentTab: AppNavTab.profile,
                onTabChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Profile',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text(AuthService.userEmail,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecond)),
              ],
            ),
          ),
          if (!_editing && _userProfile != null)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _editing = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('Edit',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ]),
              ),
            ),
          if (_editing) ...[
            GestureDetector(
              onTap: _saving ? null : _saveProfile,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _saving
                    ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : const Text('Save',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _cancelEdit,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text('Cancel',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecond)),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.06);
  }

  // ── Tab bar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: TabBar(
          controller: _tabs,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500),
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecond,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'History'),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 80.ms, duration: 400.ms);
  }

  // ── Shimmer loading ────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      child: Column(
        children: List.generate(3, (i) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: i == 0 ? 160 : 120,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(duration: 1100.ms, color: AppColors.primaryGlow)),
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.accentRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.error_outline_rounded,
                size: 32, color: AppColors.accentRed),
          ),
          const SizedBox(height: 18),
          Text('Failed to load profile',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textSecond),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Retry',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ]),
            ),
          ),
        ]),
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── Profile tab ────────────────────────────────────────────────────────────

  Widget _buildProfileTab() {
    final p = _userProfile!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      child: Form(
        key: _formKey,
        child: Column(children: [

          // Avatar card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: _cardDeco(),
            child: Column(children: [
              Container(
                width: 76, height: 76,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.avatarBlue,
                ),
                child: Center(
                  child: Text(p.initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 28)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                p.fullName.isNotEmpty ? p.fullName : 'No name set',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: 3),
              Text(p.email,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecond)),
              if (p.isAdmin) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentAmber.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.accentAmber.withOpacity(0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shield_rounded,
                        color: AppColors.accentAmber, size: 13),
                    const SizedBox(width: 5),
                    Text('Admin',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentAmber)),
                  ]),
                ),
              ],
            ]),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08),

          const SizedBox(height: 12),

          // Personal details card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SectionHeader(
                icon: Icons.person_outline_rounded,
                label: 'Personal Details',
              ),
              const SizedBox(height: 16),

              if (_editing) ...[
                _Field(
                  controller: _nameCtrl,
                  label: 'Full Name',
                  hint: 'e.g. Alex Johnson',
                  icon: Icons.badge_outlined,
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name cannot be empty' : null,
                ),
                const SizedBox(height: 12),
                _Field(
                  controller: _phoneCtrl,
                  label: 'Phone Number',
                  hint: 'e.g. +1 555 000 1234',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                _Field(
                  controller: _bioCtrl,
                  label: 'Bio',
                  hint: 'Tell us a little about yourself…',
                  icon: Icons.notes_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: _saving ? null : _saveProfile,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        const Text('Save Changes',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _cancelEdit,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Text('Cancel',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecond)),
                    ),
                  ),
                ),
              ] else ...[
                _InfoRow(icon: Icons.badge_outlined, label: 'Full Name',
                    value: p.fullName.isNotEmpty ? p.fullName : '—'),
                _divider(),
                _InfoRow(icon: Icons.email_outlined, label: 'Email',
                    value: p.email),
                _divider(),
                _InfoRow(icon: Icons.phone_outlined, label: 'Phone',
                    value: p.phone.isNotEmpty ? p.phone : '—'),
                _divider(),
                _InfoRow(icon: Icons.notes_rounded, label: 'Bio',
                    value: p.bio.isNotEmpty ? p.bio : '—',
                    multiLine: true),
              ],
            ]),
          ).animate().fadeIn(delay: 80.ms, duration: 350.ms).slideY(begin: 0.08),

          const SizedBox(height: 12),

          // Account info card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SectionHeader(
                icon: Icons.manage_accounts_outlined,
                label: 'Account',
              ),
              const SizedBox(height: 16),
              _InfoRow(
                  icon: Icons.fingerprint_rounded,
                  label: 'User ID',
                  value: p.id.length > 8 ? '${p.id.substring(0, 8)}…' : p.id),
              _divider(),
              _InfoRow(
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'Role',
                  value: p.isAdmin ? 'Administrator' : 'Student'),
              _divider(),
              _InfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Member since',
                  value: _formatDate(p.createdAt)),
            ]),
          ).animate().fadeIn(delay: 140.ms, duration: 350.ms).slideY(begin: 0.08),

          const SizedBox(height: 12),

          // Mini stats row
          Row(children: [
            _MiniStat(
                label: 'Sessions',
                value: '${_history.length}',
                icon: Icons.description_rounded,
                color: AppColors.primary),
            const SizedBox(width: 10),
            _MiniStat(
                label: 'Joined',
                value: _formatDate(p.createdAt),
                icon: Icons.calendar_today_rounded,
                color: AppColors.accentGreen),
          ]).animate().fadeIn(delay: 180.ms, duration: 350.ms).slideY(begin: 0.08),

          const SizedBox(height: 110),
        ]),
      ),
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Divider(
        color: AppColors.border.withOpacity(0.6), height: 1),
  );

  // ── History tab ────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
        child: Column(
          children: List.generate(4, (i) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(duration: 1100.ms, color: AppColors.primaryGlow)),
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.history_rounded,
                  size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text('No study sessions yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text('Upload a document to get started',
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecond)),
          ]),
        ),
      ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 110),
      itemCount: _history.length,
      itemBuilder: (ctx, i) {
        final s       = _history[i];
        final id      = s['id'] as String? ?? '';
        final summary = (s['summary'] as String? ?? '')
            .replaceAll('__pending__', 'Processing…');
        final date    = _formatDate(s['created_at'] as String? ?? '');

        final accent   = AppColors.tileAccents[i % AppColors.tileAccents.length];
        final accentBg = AppColors.tileAccentBgs[i % AppColors.tileAccentBgs.length];

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context)
                .push(slideRoute(ResultsScreen(resultId: id)));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(Icons.description_outlined,
                      size: 18, color: accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session #${i + 1}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(summary,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.textBody)),
                    const SizedBox(height: 5),
                    Row(children: [
                      Icon(Icons.access_time_rounded,
                          size: 11, color: AppColors.textSecond),
                      const SizedBox(width: 4),
                      Text(date,
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecond)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: AppColors.textSecond),
            ]),
          ),
        ).animate()
            .fadeIn(delay: Duration(milliseconds: 60 + i * 45))
            .slideX(begin: 0.05);
      },
    );
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  BoxDecoration _cardDeco() => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: AppColors.border),
  );
}

// ── Form field ────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController      controller;
  final String                     label;
  final String                     hint;
  final IconData                   icon;
  final int                        maxLines;
  final TextInputType              keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines     = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller:   controller,
    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
    maxLines:     maxLines,
    keyboardType: keyboardType,
    validator:    validator,
    decoration: InputDecoration(
      labelText:          label,
      hintText:           hint,
      alignLabelWithHint: maxLines > 1,
      labelStyle: TextStyle(color: AppColors.textSecond, fontSize: 13),
      hintStyle:  TextStyle(color: AppColors.textSecond, fontSize: 13),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(top: 2),
        child:   Icon(icon, color: AppColors.textSecond, size: 18),
      ),
      filled:    true,
      fillColor: AppColors.bg,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accentRed, width: 1.5)),
    ),
  );
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.primaryGlow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: AppColors.primary, size: 15),
    ),
    const SizedBox(width: 10),
    Text(label,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary)),
  ]);
}

// ── Mini stat card ─────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  final Color    color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.0)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecond)),
      ]),
    ),
  );
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final bool     multiLine;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.multiLine = false,
  });

  @override
  Widget build(BuildContext context) {
    if (multiLine) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppColors.textSecond, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecond)),
        ]),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  height: 1.5)),
        ),
      ]);
    }
    return Row(children: [
      Icon(icon, color: AppColors.textSecond, size: 16),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecond)),
      const Spacer(),
      Flexible(
        child: Text(value,
            textAlign: TextAlign.end,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ),
    ]);
  }
}