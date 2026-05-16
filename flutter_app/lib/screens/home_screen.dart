// lib/screens/home_screen.dart
// Home dashboard — stats, upload CTA, recent session history.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../main.dart' show slideRoute;
import '../services/profile_service.dart';
import '../models/profile.dart';
import 'login_screen.dart';
import 'upload_screen.dart';
import 'results_screen.dart';
import 'profile_screen.dart';
import 'admin/admin_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  final _api  = ApiService();
  final _profileSvc = ProfileService();

  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final uid = _auth.userId;
      if (uid != null) {
        final results = await Future.wait([
          _api.getUserResults(uid),
          _profileSvc.getProfile(uid),
        ]);
        if (mounted) setState(() {
          _sessions = results[0] as List<Map<String, dynamic>>;
          _isAdmin  = (results[1] as UserProfile).isAdmin;
        });
      }
    } catch (_) {}
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadSessions,
            color:     AppColors.primary,
            child: CustomScrollView(slivers: [

              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildStats()),
              SliverToBoxAdapter(child: _buildUploadCTA()),

              // Section title
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                  child: Text('Recent Sessions', style: AppText.subheading),
                ),
              ),

              // Session list
              if (_loading)
                SliverToBoxAdapter(child: _buildShimmer())
              else if (_sessions.isEmpty)
                SliverToBoxAdapter(child: _buildEmpty())
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildSessionTile(_sessions[i], i),
                    childCount: _sessions.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final email = _auth.userEmail ?? 'Student';
    final initial = email[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
      child: Row(children: [
        // Avatar
        Container(
          width:  44,
          height: 44,
          decoration: const BoxDecoration(
            shape:    BoxShape.circle,
            gradient: AppColors.primaryGrad,
          ),
          child: Center(
            child: Text(initial,
                style: AppText.body.copyWith(
                  color:      Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize:   18,
                )),
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome back 👋', style: AppText.label),
            Text(email,
                style:    AppText.body.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ]),
        ),

        IconButton(
          icon:    const Icon(Icons.person_rounded,
              size: 20, color: AppColors.textSecond),
          onPressed: () => Navigator.of(context).push(
              slideRoute(const ProfileScreen())),
          tooltip: 'My profile',
        ),
        if (_isAdmin)
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_rounded,
                size: 20, color: AppColors.accentAmber),
            onPressed: () => Navigator.of(context).push(
                slideRoute(const AdminDashboardScreen())),
            tooltip: 'Admin panel',
          ),
        IconButton(
          icon:    const Icon(Icons.logout_rounded,
              size: 20, color: AppColors.textMuted),
          onPressed: _signOut,
          tooltip:   'Sign out',
        ),
      ]),
    ).animate().fadeIn().slideX(begin: -0.08);
  }

  // ── Stats row ──────────────────────────────────────────────────────────────
  Widget _buildStats() {
    final totalQ = _sessions.fold<int>(0,
        (s, r) => s + ((r['quiz'] as List?)?.length ?? 0));
    final totalC = _sessions.fold<int>(0,
        (s, r) => s + ((r['flashcards'] as List?)?.length ?? 0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(children: [
        _StatCard(icon: Icons.description_rounded,
            label: 'Sessions',   value: '${_sessions.length}', color: AppColors.accentBlue),
        const SizedBox(width: 10),
        _StatCard(icon: Icons.quiz_rounded,
            label: 'Questions',  value: '$totalQ',             color: AppColors.accentGreen),
        const SizedBox(width: 10),
        _StatCard(icon: Icons.style_rounded,
            label: 'Flashcards', value: '$totalC',             color: AppColors.accentAmber),
      ]),
    ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.15);
  }

  // ── Upload CTA card ────────────────────────────────────────────────────────
  Widget _buildUploadCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: GestureDetector(
        onTap: () async {
          await Navigator.of(context).push(
              slideRoute(const UploadScreen()));
          _loadSessions(); // Refresh after returning
        },
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient:     AppColors.primaryGrad,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color:      AppColors.primaryGlow,
                blurRadius: 24,
                offset:     const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(children: [
            // Decorative circle
            Positioned(
              top:  -18,
              right: -14,
              child: Container(
                width:  88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),

            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Upload a Document',
                    style: AppText.subheading.copyWith(color: Colors.white)),
                const Spacer(),
                Icon(Icons.cloud_upload_outlined,
                    color: Colors.white.withOpacity(0.3), size: 36),
              ]),

              const SizedBox(height: 6),

              Text(
                'PDF or DOCX  ·  up to 10 MB  ·  20 pages',
                style: AppText.caption.copyWith(
                    color: Colors.white.withOpacity(0.72)),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.28)),
                ),
                child: Text(
                  'Get Started →',
                  style: AppText.label.copyWith(
                      color: Colors.white, fontSize: 12),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ).animate().fadeIn(delay: 210.ms).slideY(begin: 0.2);
  }

  // ── Session tile ───────────────────────────────────────────────────────────
  Widget _buildSessionTile(Map<String, dynamic> r, int index) {
    final summary   = (r['summary'] as String? ?? '')
        .replaceAll('__pending__', 'Processing…');
    final quizCount = (r['quiz']       as List?)?.length ?? 0;
    final cardCount = (r['flashcards'] as List?)?.length ?? 0;
    final id        = r['id'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        onTap: () {
          if (id.isEmpty) return;
          Navigator.of(context).push(
              slideRoute(ResultsScreen(resultId: id)));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(color: AppColors.borderLight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width:  36,
                height: 36,
                decoration: BoxDecoration(
                  color:        AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.description_rounded,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Study Session #${index + 1}',
                  style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textMuted),
            ]),

            if (summary.isNotEmpty && summary != 'Processing…') ...[
              const SizedBox(height: 8),
              Text(
                summary,
                maxLines:  2,
                overflow:  TextOverflow.ellipsis,
                style:     AppText.caption,
              ),
            ],

            const SizedBox(height: 10),

            Row(children: [
              _Chip(
                label: '$quizCount Questions',
                icon:  Icons.quiz_rounded,
                color: AppColors.accentGreen,
              ),
              const SizedBox(width: 8),
              _Chip(
                label: '$cardCount Cards',
                icon:  Icons.style_rounded,
                color: AppColors.accentAmber,
              ),
            ]),
          ]),
        ),
      ),
    ).animate().fadeIn(delay: (280 + index * 70).ms).slideX(begin: 0.08);
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(children: [
          const Icon(Icons.folder_open_rounded,
              size: 52, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text('No sessions yet', style: AppText.body),
          const SizedBox(height: 4),
          Text('Upload a document to get started', style: AppText.caption),
        ]),
      ),
    );
  }

  // ── Loading shimmer ────────────────────────────────────────────────────────
  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: List.generate(3, (i) => Container(
          margin:     const EdgeInsets.only(bottom: 10),
          height:     88,
          decoration: BoxDecoration(
            color:        AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(duration: 1200.ms, color: AppColors.border)),
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: AppText.display(20).copyWith(color: color)),
          Text(label,
              style: AppText.label.copyWith(
                  color: color.withOpacity(0.75))),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;

  const _Chip({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: AppText.label.copyWith(color: color)),
      ]),
    );
  }
}
