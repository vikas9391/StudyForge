// lib/screens/admin/admin_dashboard_screen.dart
// Admin overview — platform stats, recent signups, quick navigation.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart';
import '../../models/profile.dart';
import '../../services/profile_service.dart';
import 'admin_users_screen.dart';
import '../../main.dart' show slideRoute;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _profileSvc = ProfileService();
  AdminStats? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final s = await _profileSvc.getAdminStats();
      if (mounted) setState(() { _stats = s; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading:  BackButton(color: AppColors.textSecond),
        title:    Text('Admin Dashboard', style: AppText.subheading),
        actions: [
          IconButton(
            icon:    const Icon(Icons.refresh_rounded,
                color: AppColors.textSecond),
            onPressed: _load,
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
                : RefreshIndicator(
                    onRefresh: _load,
                    color:     AppColors.primary,
                    child:     _buildBody(),
                  ),
      ),
    );
  }

  Widget _buildBody() {
    final s = _stats!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [

        // ── Admin badge header ──────────────────────────────────────────────
        Container(
          padding:     const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient:     AppColors.primaryGrad,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
                color: AppColors.primaryGlow, blurRadius: 20,
                offset: const Offset(0, 6))]),
          child: Row(children: [
            const Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white, size: 32),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Admin Panel', style: AppText.heading
                  .copyWith(color: Colors.white)),
              Text('Full platform access',
                  style: AppText.caption.copyWith(
                      color: Colors.white.withOpacity(0.75))),
            ]),
          ]),
        ).animate().fadeIn().slideY(begin: 0.1),

        const SizedBox(height: 20),

        // ── Stats grid ──────────────────────────────────────────────────────
        Text('Platform Overview', style: AppText.subheading),
        const SizedBox(height: 12),

        GridView.count(
          shrinkWrap: true,
          physics:    const NeverScrollableScrollPhysics(),
          crossAxisCount:   2,
          crossAxisSpacing: 10,
          mainAxisSpacing:  10,
          childAspectRatio: 1.5,
          children: [
            _StatCard(
              icon:  Icons.people_rounded,
              label: 'Total Users',
              value: '${s.totalUsers}',
              color: AppColors.accentBlue,
            ),
            _StatCard(
              icon:  Icons.description_rounded,
              label: 'Total Sessions',
              value: '${s.totalSessions}',
              color: AppColors.primary,
            ),
            _StatCard(
              icon:  Icons.today_rounded,
              label: 'Sessions Today',
              value: '${s.sessionsToday}',
              color: AppColors.accentGreen,
            ),
            _StatCard(
              icon:  Icons.trending_up_rounded,
              label: 'Avg / User',
              value: s.totalUsers > 0
                  ? (s.totalSessions / s.totalUsers).toStringAsFixed(1)
                  : '0',
              color: AppColors.accentAmber,
            ),
          ],
        ).animate().fadeIn(delay: 120.ms),

        const SizedBox(height: 24),

        // ── Quick actions ───────────────────────────────────────────────────
        Text('Quick Actions', style: AppText.subheading),
        const SizedBox(height: 12),

        _ActionTile(
          icon:     Icons.people_alt_rounded,
          label:    'Manage Users',
          subtitle: '${s.totalUsers} registered users',
          color:    AppColors.accentBlue,
          onTap: () => Navigator.of(context).push(
              slideRoute(const AdminUsersScreen())),
        ),

        const SizedBox(height: 10),

        _ActionTile(
          icon:     Icons.bar_chart_rounded,
          label:    'Sessions Overview',
          subtitle: '${s.sessionsToday} new today',
          color:    AppColors.accentGreen,
          onTap: () => Navigator.of(context).push(
              slideRoute(const AdminUsersScreen())),
        ),

        const SizedBox(height: 24),

        // ── Recent signups ──────────────────────────────────────────────────
        Text('Recent Sign-ups', style: AppText.subheading),
        const SizedBox(height: 12),

        if (s.recentSignups.isEmpty)
          Center(child: Text('No users yet', style: AppText.caption))
        else
          ...s.recentSignups.asMap().entries.map((e) {
            final i    = e.key;
            final u    = e.value;
            final email = u['email'] as String? ?? '';
            final date  = _fmtDate(u['created_at'] as String? ?? '');
            return Container(
              margin:     const EdgeInsets.only(bottom: 8),
              padding:    const EdgeInsets.all(14),
              decoration: cardDecoration(),
              child: Row(children: [
                Container(
                  width:  38, height: 38,
                  decoration: BoxDecoration(
                    color:        AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text(
                    email.isNotEmpty ? email[0].toUpperCase() : '?',
                    style: AppText.body.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(email, style: AppText.bodySmall
                      .copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text('Joined $date', style: AppText.caption),
                ])),
              ]),
            ).animate().fadeIn(delay: (300 + i * 60).ms).slideX(begin: 0.06);
          }),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildError() => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline_rounded,
        size: 48, color: AppColors.accentRed),
    const SizedBox(height: 14),
    Text('Failed to load stats', style: AppText.subheading),
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
    } catch (_) { return iso.substring(0, 10); }
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _StatCard({required this.icon, required this.label,
      required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding:    const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(14),
      border:       Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Icon(icon, color: color, size: 22),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: AppText.display(22).copyWith(color: color)),
        Text(label, style: AppText.label
            .copyWith(color: color.withOpacity(0.75))),
      ]),
    ]),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label,
      required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding:    const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Row(children: [
        Container(
          width:  44, height: 44,
          decoration: BoxDecoration(
            color:        color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.bodySmall
              .copyWith(fontWeight: FontWeight.w700)),
          Text(subtitle, style: AppText.caption),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: AppColors.textMuted),
      ]),
    ),
  );
}
