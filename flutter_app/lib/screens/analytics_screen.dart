// lib/screens/analytics_screen.dart
// Study analytics: weak-topic heatmap + accuracy-over-time chart.
// Restyled to match HomeScreen V3 — warm bg, surface cards, shared nav.
// BUG FIX: header Row pill wrapped in Flexible to prevent horizontal overflow
// BUG FIX: _MiniPill Row → Wrap to prevent 1343px vertical collapse
// BUG FIX: bar height 100 → 90 to prevent vertical overflow in chart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../models/study_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_bottom_nav.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _api  = ApiService();

  List<WeakTopic>      _weak     = [];
  List<AccuracyPoint>  _accuracy = [];
  Map<String, dynamic> _summary  = {};

  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = AuthService.userId;
      if (uid.isEmpty) throw 'Not signed in.';
      final results = await Future.wait([
        _api.getWeakTopics(uid),
        _api.getAccuracyOverTime(uid),
        _api.getAnalyticsSummary(uid),
      ]);
      if (mounted) {
        setState(() {
          _weak     = results[0] as List<WeakTopic>;
          _accuracy = results[1] as List<AccuracyPoint>;
          _summary  = results[2] as Map<String, dynamic>;
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
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
                Expanded(
                  child: _loading
                      ? _buildShimmer()
                      : _error != null
                      ? _buildError()
                      : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildSummaryCards()),
                        SliverToBoxAdapter(child: _buildAccuracyChart()),
                        SliverToBoxAdapter(child: _buildWeakTopicsSection()),
                        const SliverToBoxAdapter(child: SizedBox(height: 110)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: AppBottomNav(
                currentTab: AppNavTab.analytics,
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
                Text('Analytics',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text('Track your progress over time',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecond,
                        fontWeight: FontWeight.w400)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _load,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(Icons.refresh_rounded,
                  size: 17, color: AppColors.textSecond),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.06);
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
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.bar_chart_rounded,
                size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text('No analytics yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('Complete some quizzes to see your stats.',
              style: TextStyle(
                  fontSize: 14, height: 1.55, color: AppColors.textSecond),
              textAlign: TextAlign.center),
        ]),
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── Shimmer loading ────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
      child: Column(
        children: List.generate(4, (i) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: i == 0 ? 100 : 140,
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

  // ── Summary cards ──────────────────────────────────────────────────────────

  Widget _buildSummaryCards() {
    final attempts = _summary['total_attempts'] as int? ?? 0;
    final avgAcc   = _summary['avg_accuracy']   as int? ?? 0;
    final streak   = _summary['study_streak']   as int? ?? 0;
    final best     = _summary['best_session']   as Map?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('Overview',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _StatCard(
                emoji: '📝',
                label: 'Attempts',
                value: '$attempts',
                accentColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                emoji: '🎯',
                label: 'Avg accuracy',
                value: '$avgAcc%',
                accentColor: AppColors.accentGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                emoji: '🔥',
                label: 'Study streak',
                value: '${streak}d',
                accentColor: AppColors.accentAmber,
              ),
            ),
          ]),
          if (best != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.accentGreen.withOpacity(0.35), width: 1.5),
              ),
              child: Row(children: [
                const Text('🏆', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Best session',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentGreen,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(best['name'] as String? ?? 'Unnamed',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.accentGreen.withOpacity(0.25)),
                  ),
                  child: Text('${best['pct']}%',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentGreen)),
                ),
              ]),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }

  // ── Accuracy chart ─────────────────────────────────────────────────────────

  Widget _buildAccuracyChart() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Accuracy over time',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Last 30 days',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_accuracy.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                      'No quiz data yet — complete a quiz to start tracking.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecond),
                      textAlign: TextAlign.center),
                ),
              )
            else
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _accuracy.map((point) {
                    final maxPct = _accuracy.fold<int>(
                        0, (m, p) => p.pct > m ? p.pct : m);
                    final frac =
                    maxPct > 0 ? point.pct / maxPct : 0.0;
                    final color = point.pct >= 70
                        ? AppColors.accentGreen
                        : point.pct >= 40
                        ? AppColors.accentAmber
                        : AppColors.accentRed;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${point.pct}%',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: color,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: Duration(
                                  milliseconds: 400 +
                                      _accuracy.indexOf(point) * 30),
                              curve: Curves.easeOut,
                              // BUG FIX: was 100, reduced to 90 to stay within 120px container
                              height: 90 * frac,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              point.date.substring(5),
                              style: TextStyle(
                                  fontSize: 7,
                                  color: AppColors.textSecond),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 400.ms);
  }

  // ── Weak topics section ────────────────────────────────────────────────────

  Widget _buildWeakTopicsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Weak topics',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                // BUG FIX: wrapped in Flexible to prevent horizontal overflow
                if (_weak.isNotEmpty)
                  Flexible(
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentRed.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${_weak.length} topics',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentRed)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
                'Topics you consistently get wrong across all sessions.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecond)),
          ),
          const SizedBox(height: 12),
          if (_weak.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Column(children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 32, color: AppColors.accentGreen),
                  const SizedBox(height: 10),
                  Text('No weak topics yet — keep quizzing!',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecond),
                      textAlign: TextAlign.center),
                ]),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: List.generate(_weak.length, (i) {
                  final isLast = i == _weak.length - 1;
                  return _buildTopicRow(_weak[i], i, isLast);
                }),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  Widget _buildTopicRow(WeakTopic topic, int index, bool isLast) {
    final pct   = topic.errorRate;
    final color = pct >= 0.7
        ? AppColors.accentRed
        : pct >= 0.4
        ? AppColors.accentAmber
        : AppColors.accentGreen;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
            bottom: BorderSide(
                color: AppColors.border.withOpacity(0.5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('${index + 1}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(topic.topic,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${(pct * 100).round()}% wrong',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: Duration(milliseconds: 500 + index * 40),
              curve: Curves.easeOut,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                backgroundColor: color.withOpacity(0.10),
                color: color,
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // BUG FIX: Row → Wrap to prevent 1343px vertical collapse when pills overflow
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _MiniPill(
                  label: '${topic.wrong} wrong', color: AppColors.accentRed),
              _MiniPill(
                  label: '${topic.correct} correct',
                  color: AppColors.accentGreen),
              _MiniPill(
                  label: '${topic.total} total',
                  color: AppColors.textSecond),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 220 + index * 45))
        .slideX(begin: 0.05);
  }
}

// ─── Stat card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color  accentColor;

  const _StatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, t, __) => Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    height: 1.0)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecond)),
        ],
      ),
    );
  }
}

// ─── Mini pill ────────────────────────────────────────────────────────────────

class _MiniPill extends StatelessWidget {
  final String label;
  final Color  color;
  const _MiniPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color)),
  );
}