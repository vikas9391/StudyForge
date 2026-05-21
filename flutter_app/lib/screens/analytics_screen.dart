// lib/screens/analytics_screen.dart
// Study analytics: weak-topic heatmap + accuracy-over-time chart.

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
  final _auth = AuthService();

  List<WeakTopic>    _weak     = [];
  List<AccuracyPoint> _accuracy = [];
  Map<String, dynamic> _summary = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = _auth.userId;
      if (uid == null) throw 'Not signed in.';
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Analytics', style: AppText.subheading),
      ),
      body: Stack(
        children: [

          // Main Content
          _loading
              ? const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          )
              : _error != null
              ? _buildError()
              : RefreshIndicator(
            onRefresh: _load,
            color: AppColors.primary,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [

                _buildSummaryCards(),

                const SizedBox(height: 24),

                _buildAccuracyChart(),

                const SizedBox(height: 24),

                _buildWeakTopicsHeatmap(),

                // IMPORTANT SPACER
                const SizedBox(height: 110),
              ],
            ),
          ),

          // Floating Bottom Nav
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppBottomNav(
              currentTab: AppNavTab.analytics,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.bar_chart_rounded, size: 52, color: AppColors.textMuted),
      const SizedBox(height: 16),
      Text('No analytics yet', style: AppText.subheading),
      const SizedBox(height: 8),
      Text('Complete some quizzes to see your stats.',
          style: AppText.caption, textAlign: TextAlign.center),
    ]),
  );

  // ── Summary cards ─────────────────────────────────────────────────────────

  Widget _buildSummaryCards() {
    final attempts = _summary['total_attempts'] as int? ?? 0;
    final avgAcc   = _summary['avg_accuracy']   as int? ?? 0;
    final streak   = _summary['study_streak']   as int? ?? 0;
    final best     = _summary['best_session']   as Map?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Overview', style: AppText.subheading.copyWith(fontSize: 16)),
      const SizedBox(height: 12),
      Row(children: [
        _StatCard(emoji: '📝', label: 'Attempts',   value: '$attempts', color: AppColors.primary),
        const SizedBox(width: 10),
        _StatCard(emoji: '🎯', label: 'Avg accuracy', value: '$avgAcc%', color: AppColors.accentGreen),
        const SizedBox(width: 10),
        _StatCard(emoji: '🔥', label: 'Study streak', value: '${streak}d', color: AppColors.accentAmber),
      ]),
      if (best != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accentGreen.withOpacity(0.25)),
          ),
          child: Row(children: [
            Text('🏆', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Best session', style: AppText.label.copyWith(color: AppColors.accentGreen)),
                Text(best['name'] as String? ?? 'Unnamed',
                    style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            Text('${best['pct']}%',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                    color: AppColors.accentGreen)),
          ]),
        ),
      ],
    ]).animate().fadeIn();
  }

  // ── Accuracy chart (simple bar chart) ────────────────────────────────────

  Widget _buildAccuracyChart() {
    if (_accuracy.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: cardDecoration(),
        child: Center(
          child: Text('No quiz data yet — complete a quiz to start tracking.',
              style: AppText.caption, textAlign: TextAlign.center),
        ),
      );
    }

    final maxPct = _accuracy.fold<int>(0, (m, p) => p.pct > m ? p.pct : m);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Accuracy over time', style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Last 30 days', style: AppText.caption),
        const SizedBox(height: 20),

        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _accuracy.map((point) {
              final frac = maxPct > 0 ? point.pct / maxPct : 0.0;
              final color = point.pct >= 70 ? AppColors.accentGreen
                  : point.pct >= 40 ? AppColors.accentAmber
                  : AppColors.accentRed;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${point.pct}%',
                          style: TextStyle(fontSize: 8, color: color,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: Duration(milliseconds: 400 + _accuracy.indexOf(point) * 30),
                        curve: Curves.easeOut,
                        height: 100 * frac,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        point.date.substring(5), // MM-DD
                        style: const TextStyle(fontSize: 7, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    ).animate().fadeIn(delay: 100.ms);
  }

  // ── Weak topic heatmap ────────────────────────────────────────────────────

  Widget _buildWeakTopicsHeatmap() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Weak topics', style: AppText.subheading.copyWith(fontSize: 16)),
      const SizedBox(height: 4),
      Text('Topics you consistently get wrong across all sessions.',
          style: AppText.caption),
      const SizedBox(height: 12),

      if (_weak.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: cardDecoration(),
          child: Center(
            child: Text('No weak topics yet — keep quizzing!',
                style: AppText.caption, textAlign: TextAlign.center),
          ),
        )
      else
        ...List.generate(_weak.length, (i) => _buildTopicRow(_weak[i], i)),
    ]).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildTopicRow(WeakTopic topic, int index) {
    final pct   = topic.errorRate;
    final color = pct >= 0.7 ? AppColors.accentRed
        : pct >= 0.4 ? AppColors.accentAmber
        : AppColors.accentGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Rank badge
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(topic.topic,
                style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          Text('${(pct * 100).round()}% wrong',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 8),

        // Error bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: Duration(milliseconds: 500 + index * 40),
            curve: Curves.easeOut,
            builder: (_, value, __) => LinearProgressIndicator(
              value: value,
              backgroundColor: color.withOpacity(0.12),
              color: color,
              minHeight: 6,
            ),
          ),
        ),

        const SizedBox(height: 6),
        Row(children: [
          Text('${topic.wrong} wrong',
              style: TextStyle(fontSize: 11, color: AppColors.accentRed)),
          const SizedBox(width: 12),
          Text('${topic.correct} correct',
              style: TextStyle(fontSize: 11, color: AppColors.accentGreen)),
          const SizedBox(width: 12),
          Text('${topic.total} total',
              style: AppText.label),
        ]),
      ]),
    ).animate().fadeIn(delay: Duration(milliseconds: 100 + index * 40))
        .slideX(begin: 0.06);
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color  color;

  const _StatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                color: color.withOpacity(0.75))),
      ]),
    ),
  );
}