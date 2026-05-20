// lib/screens/profile_screen.dart
// User profile screen — edit name / bio / phone, view study history, stats.

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
    final uid = _auth.userId;
    if (uid == null) return;

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
    final uid = _auth.userId;
    if (uid == null) return;

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
      content:         Text(msg),
      backgroundColor: error ? AppColors.accentRed : AppColors.accentGreen,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation:       0,
        leading:  BackButton(color: AppColors.textSecond),
        title:    Text('My Profile', style: AppText.subheading),
        actions: [
          if (!_editing && _userProfile != null)
            TextButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon:  const Icon(Icons.edit_rounded,
                  color: AppColors.primary, size: 16),
              label: Text('Edit',
                  style: AppText.body.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          if (_editing) ...[
            TextButton(
              onPressed: _saving ? null : _saveProfile,
              child: _saving
                  ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2))
                  : Text('Save',
                  style: AppText.body.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: _cancelEdit,
              child: Text('Cancel',
                  style: AppText.body.copyWith(color: AppColors.textSecond)),
            ),
          ],
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color:        AppColors.borderLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller:  _tabs,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color:        AppColors.surface,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color:      const Color(0xFF1A1814).withOpacity(0.06),
                      blurRadius: 8,
                      offset:     const Offset(0, 2),
                    ),
                  ],
                ),
                labelStyle: AppText.label.copyWith(
                    color: AppColors.primary, letterSpacing: 0.4),
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
      child: Form(
        key: _formKey,
        child: Column(children: [

          // ── Avatar + display name ──────────────────────────────────────
          Container(
            padding:    const EdgeInsets.all(24),
            decoration: _cardDeco(),
            child: Column(children: [
              Container(
                width:  80,
                height: 80,
                decoration: const BoxDecoration(
                  shape:    BoxShape.circle,
                  gradient: AppColors.primaryGrad,
                ),
                child: Center(
                  child: Text(p.initials,
                      style: AppText.display(28).copyWith(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                p.fullName.isNotEmpty ? p.fullName : 'No name set',
                style: AppText.subheading,
              ),
              const SizedBox(height: 2),
              Text(p.email, style: AppText.caption),
              if (p.isAdmin) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color:        AppColors.accentAmber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border:       Border.all(
                        color: AppColors.accentAmber.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shield_rounded,
                        color: AppColors.accentAmber, size: 13),
                    const SizedBox(width: 5),
                    Text('Admin',
                        style: AppText.label.copyWith(
                            color: AppColors.accentAmber)),
                  ]),
                ),
              ],
            ]),
          ).animate().fadeIn().slideY(begin: 0.1),

          const SizedBox(height: 16),

          // ── Edit / display fields ──────────────────────────────────────
          Container(
            padding:    const EdgeInsets.all(20),
            decoration: _cardDeco(),
            child: Column(children: [

              _SectionHeader(
                icon:  Icons.person_outline_rounded,
                label: 'Personal Details',
              ),
              const SizedBox(height: 16),

              if (_editing) ...[
                _Field(
                  controller: _nameCtrl,
                  label:      'Full Name',
                  hint:       'e.g. Alex Johnson',
                  icon:       Icons.badge_outlined,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                _Field(
                  controller:   _phoneCtrl,
                  label:        'Phone Number',
                  hint:         'e.g. +1 555 000 1234',
                  icon:         Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),

                _Field(
                  controller: _bioCtrl,
                  label:      'Bio',
                  hint:       'Tell us a little about yourself…',
                  icon:       Icons.notes_rounded,
                  maxLines:   3,
                ),

                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _saving ? null : _saveProfile,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height:   50,
                      decoration: BoxDecoration(
                        gradient:     _saving ? null : AppColors.primaryGrad,
                        color:        _saving ? AppColors.border : null,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _saving
                            ? []
                            : [BoxShadow(
                            color:      AppColors.primaryGlow,
                            blurRadius: 14,
                            offset:     const Offset(0, 4))],
                      ),
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.check_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text('Save Changes',
                              style: AppText.body.copyWith(
                                  color:      Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _cancelEdit,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Text('Cancel',
                        style: AppText.body.copyWith(
                            color: AppColors.textSecond)),
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
          ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.1),

          const SizedBox(height: 16),

          // ── Account info ───────────────────────────────────────────────
          Container(
            padding:    const EdgeInsets.all(20),
            decoration: _cardDeco(),
            child: Column(children: [
              _SectionHeader(
                icon:  Icons.manage_accounts_outlined,
                label: 'Account',
              ),
              const SizedBox(height: 16),
              _InfoRow(icon: Icons.fingerprint_rounded, label: 'User ID',
                  value: p.id.length > 8 ? '${p.id.substring(0, 8)}…' : p.id),
              _divider(),
              _InfoRow(icon: Icons.admin_panel_settings_rounded, label: 'Role',
                  value: p.isAdmin ? 'Administrator' : 'Student'),
              _divider(),
              _InfoRow(icon: Icons.calendar_today_rounded, label: 'Member since',
                  value: _formatDate(p.createdAt)),
            ]),
          ).animate().fadeIn(delay: 140.ms).slideY(begin: 0.1),

          const SizedBox(height: 16),

          // ── Mini stats ─────────────────────────────────────────────────
          Row(children: [
            _MiniStat(label: 'Sessions', value: '${_history.length}',
                icon: Icons.description_rounded, color: AppColors.accentBlue),
            const SizedBox(width: 10),
            _MiniStat(label: 'Joined', value: _formatDate(p.createdAt),
                icon: Icons.calendar_today_rounded, color: AppColors.accentGreen),
          ]).animate().fadeIn(delay: 180.ms).slideY(begin: 0.1),

        ]),
      ),
    );
  }

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child:   Divider(color: AppColors.borderLight, height: 1),
  );

  // ── History tab ───────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator(
          color: AppColors.primary, strokeWidth: 2.5));
    }
    if (_history.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding:    const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color:  AppColors.primary.withOpacity(0.06),
              shape:  BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded,
                size: 36, color: AppColors.primary.withOpacity(0.4)),
          ),
          const SizedBox(height: 16),
          Text('No study sessions yet',
              style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Upload a document to get started', style: AppText.caption),
        ]),
      );
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
            decoration: _cardDeco(),
            child: Row(children: [
              Container(
                width:  42,
                height: 42,
                decoration: BoxDecoration(
                  gradient:     AppColors.primaryGrad,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('${i + 1}',
                      style: AppText.body.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session #${i + 1}',
                        style: AppText.bodySmall.copyWith(
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(summary,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: AppText.caption),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.access_time_rounded,
                          size: 11, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(date,
                          style: AppText.label.copyWith(
                              color: AppColors.textMuted, fontSize: 10)),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textMuted),
            ]),
          ),
        ).animate().fadeIn(delay: (i * 50).ms).slideX(begin: 0.06);
      },
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline_rounded,
          size: 48, color: AppColors.accentRed),
      const SizedBox(height: 14),
      Text('Failed to load profile', style: AppText.subheading),
      const SizedBox(height: 6),
      Text(_error!, style: AppText.caption, textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton.icon(
          onPressed: _load,
          icon:  const Icon(Icons.refresh_rounded),
          label: const Text('Retry')),
    ]),
  );

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
    color:        AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    border:       Border.all(color: AppColors.border),
    boxShadow: [
      BoxShadow(
        color:      const Color(0xFF1A1814).withOpacity(0.04),
        blurRadius: 10,
        offset:     const Offset(0, 2),
      ),
    ],
  );
}

// ── Reusable form field ───────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController       controller;
  final String                      label;
  final String                      hint;
  final IconData                    icon;
  final int                         maxLines;
  final TextInputType               keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines    = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller:   controller,
    style:        AppText.body,
    maxLines:     maxLines,
    keyboardType: keyboardType,
    validator:    validator,
    decoration: InputDecoration(
      labelText:          label,
      hintText:           hint,
      alignLabelWithHint: maxLines > 1,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(top: 2),
        child:   Icon(icon, color: AppColors.textMuted, size: 20),
      ),
    ),
  );
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding:    const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color:        AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: AppColors.primary, size: 16),
    ),
    const SizedBox(width: 10),
    Text(label,
        style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
  ]);
}

// ── Small helpers ─────────────────────────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  final Color    color;
  const _MiniStat({required this.label, required this.value,
    required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color:      const Color(0xFF1A1814).withOpacity(0.04),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding:    const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 8),
        Text(value, style: AppText.subheading.copyWith(
            color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: AppText.label.copyWith(
            color: AppColors.textSecond, fontSize: 10)),
      ]),
    ),
  );
}

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
          Icon(icon, color: AppColors.textMuted, size: 17),
          const SizedBox(width: 10),
          Text(label, style: AppText.caption),
        ]),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 27),
          child:   Text(value,
              style: AppText.bodySmall.copyWith(
                  fontWeight: FontWeight.w500, height: 1.5)),
        ),
      ]);
    }
    return Row(children: [
      Icon(icon, color: AppColors.textMuted, size: 17),
      const SizedBox(width: 10),
      Text(label, style: AppText.caption),
      const Spacer(),
      Flexible(
        child: Text(value,
            textAlign: TextAlign.end,
            style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}