// lib/screens/sr_review_screen.dart
// Spaced repetition review session.
//
// Shows cards due today one at a time.
// User taps to reveal the answer, then rates recall quality (Again/Hard/Good/Easy).
// Ratings map to SM-2 quality scores: Again=1, Hard=2, Good=3, Easy=5.
// After all cards, shows a completion summary.
// FIX: API call fired in background — UI advances immediately on tap
// FIX: All emojis replaced with icons for a professional appearance

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import '../core/constants.dart';
import '../models/study_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_bottom_nav.dart';

class SrReviewScreen extends StatefulWidget {
  const SrReviewScreen({super.key});

  @override
  State<SrReviewScreen> createState() => _SrReviewScreenState();
}

class _SrReviewScreenState extends State<SrReviewScreen>
    with SingleTickerProviderStateMixin {
  final _api  = ApiService();
  final _auth = AuthService();

  List<SrSession> _sessions   = [];
  List<SrCard>    _queue      = [];
  List<String>    _resultIds  = [];

  int  _currentIndex = 0;
  bool _revealed     = false;
  bool _loading      = true;
  bool _submitting   = false;
  String? _error;

  int _reviewed = 0;
  int _again    = 0;
  int _hard     = 0;
  int _good     = 0;
  int _easy     = 0;

  AppNavTab _currentTab = AppNavTab.review;

  late AnimationController _flipCtrl;
  late Animation<double>   _flipAnim;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic));
    _loadDueCards();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDueCards() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = _auth.userId;
      if (uid == null) throw 'Not signed in.';
      _sessions = await _api.getDueCards(uid);
      _queue     = [];
      _resultIds = [];
      for (final s in _sessions) {
        for (final c in s.cards) {
          _queue.add(c);
          _resultIds.add(s.resultId);
        }
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  SrCard get _current => _queue[_currentIndex];

  void _rate(int quality) {
    // Guard: ignore double-taps
    if (_submitting) return;
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);

    // ── Fire API call in background — do NOT await it ──────────────────────
    final uid      = _auth.userId ?? '';
    final resultId = _resultIds[_currentIndex];
    final cardIdx  = _current.cardIndex;
    _api.submitSrReview(
      userId:    uid,
      resultId:  resultId,
      cardIndex: cardIdx,
      quality:   quality,
    ).catchError((_) {});   // swallow errors silently

    // ── Update counters immediately ────────────────────────────────────────
    _reviewed++;
    if (quality <= 1)      _again++;
    else if (quality == 2) _hard++;
    else if (quality == 3) _good++;
    else                   _easy++;

    // ── Advance UI immediately ─────────────────────────────────────────────
    if (_currentIndex + 1 >= _queue.length) {
      setState(() { _submitting = false; _currentIndex = _queue.length; });
    } else {
      _flipCtrl.reset();
      setState(() {
        _submitting   = false;
        _currentIndex++;
        _revealed     = false;
      });
    }
  }

  void _reveal() {
    if (_revealed) return;
    HapticFeedback.lightImpact();
    _flipCtrl.forward();
    setState(() => _revealed = true);
  }

  bool get _done => _currentIndex >= _queue.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Due Cards', style: AppText.subheading),
        actions: [
          if (!_loading && !_done && _queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_currentIndex + 1} / ${_queue.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecond,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
              : _error != null
              ? _buildError()
              : _queue.isEmpty
              ? _buildAllCaughtUp()
              : _done
              ? _buildSummary()
              : _buildReviewCard(),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: AppBottomNav(
              currentTab: _currentTab,
              onTabChanged: (tab) => setState(() => _currentTab = tab),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: AppColors.accentRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.error_outline_rounded,
              size: 28, color: AppColors.accentRed),
        ),
        const SizedBox(height: 16),
        Text('Something went wrong',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecond)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _loadDueCards,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Retry',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ),
        ),
      ]),
    ),
  );

  // ── All caught up ──────────────────────────────────────────────────────────

  Widget _buildAllCaughtUp() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.check_circle_outline_rounded,
              size: 32, color: AppColors.accentGreen),
        ),
        const SizedBox(height: 20),
        Text('All caught up',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.4)),
        const SizedBox(height: 8),
        Text('No cards are due for review today.\nCheck back tomorrow.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppColors.textSecond)),
      ]),
    ).animate().fadeIn().scale(begin: const Offset(0.92, 0.92)),
  );

  // ── Summary ────────────────────────────────────────────────────────────────

  Widget _buildSummary() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 16),

      // Header
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.done_all_rounded,
                size: 24, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Session complete',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text('$_reviewed card${_reviewed == 1 ? '' : 's'} reviewed',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecond)),
            ]),
          ),
        ]),
      ),

      const SizedBox(height: 16),

      // Breakdown
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _SummaryRow(
              icon: Icons.replay_rounded,
              label: 'Again',
              count: _again,
              color: AppColors.accentRed),
          const SizedBox(height: 10),
          _SummaryRow(
              icon: Icons.trending_down_rounded,
              label: 'Hard',
              count: _hard,
              color: AppColors.accentAmber),
          const SizedBox(height: 10),
          _SummaryRow(
              icon: Icons.check_rounded,
              label: 'Good',
              count: _good,
              color: AppColors.accentGreen),
          const SizedBox(height: 10),
          _SummaryRow(
              icon: Icons.bolt_rounded,
              label: 'Easy',
              count: _easy,
              color: AppColors.accentBlue),
        ]),
      ),

      const Spacer(),
      const SizedBox(height: 110),

      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(
            child: Text('Done',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ),
      ),
    ]).animate().fadeIn(),
  );

  // ── Review card ────────────────────────────────────────────────────────────

  Widget _buildReviewCard() {
    final card     = _current;
    final progress = (_currentIndex + 1) / _queue.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:           progress,
            backgroundColor: AppColors.border,
            color:           AppColors.primary,
            minHeight:       4,
          ),
        ),
        const SizedBox(height: 24),

        // Card
        Expanded(
          child: GestureDetector(
            onTap: _revealed ? null : _reveal,
            child: AnimatedBuilder(
              animation: _flipAnim,
              builder: (_, __) {
                final angle     = _flipAnim.value * math.pi;
                final isBack    = _flipAnim.value >= 0.5;
                final faceAngle = isBack ? angle - math.pi : angle;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(faceAngle),
                  child: isBack
                      ? _CardFace(
                    label:  'ANSWER',
                    text:   card.back,
                    color:  AppColors.accentGreen,
                    isBack: true,
                  )
                      : _CardFace(
                    label:  'QUESTION',
                    text:   card.front,
                    color:  AppColors.primary,
                    isBack: false,
                    hint:   'Tap to reveal answer',
                  ),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Rating buttons
        AnimatedOpacity(
          opacity:  _revealed ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_revealed,
            child: Column(children: [
              Text('Rate your recall',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecond,
                      letterSpacing: 0.2)),
              const SizedBox(height: 10),
              Row(children: [
                _RatingButton(
                    label: 'Again',
                    sublabel: 'Forgot',
                    color: AppColors.accentRed,
                    quality: 1,
                    onTap: _rate),
                const SizedBox(width: 4),
                _RatingButton(
                    label: 'Hard',
                    sublabel: 'Difficult',
                    color: AppColors.accentAmber,
                    quality: 2,
                    onTap: _rate),
                const SizedBox(width: 4),
                _RatingButton(
                    label: 'Good',
                    sublabel: 'Correct',
                    color: AppColors.accentGreen,
                    quality: 3,
                    onTap: _rate),
                const SizedBox(width: 4),
                _RatingButton(
                    label: 'Easy',
                    sublabel: 'Perfect',
                    color: AppColors.accentBlue,
                    quality: 5,
                    onTap: _rate),
              ]),
            ]),
          ),
        ),

        const SizedBox(height: 110),
      ]),
    );
  }
}

// ── Card face ─────────────────────────────────────────────────────────────────

class _CardFace extends StatelessWidget {
  final String  label;
  final String  text;
  final Color   color;
  final bool    isBack;
  final String? hint;

  const _CardFace({
    required this.label,
    required this.text,
    required this.color,
    required this.isBack,
    this.hint,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: isBack
          ? AppColors.accentGreen.withOpacity(0.04)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withOpacity(0.30), width: 1.5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Label chip
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.8)),
      ),
      const Spacer(),
      // Card text
      Text(text,
          style: TextStyle(
              fontSize: 18,
              height: 1.55,
              fontWeight: isBack ? FontWeight.w400 : FontWeight.w700,
              color: AppColors.textPrimary)),
      const Spacer(),
      // Hint / flip indicator
      if (hint != null)
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.touch_app_outlined,
                size: 13, color: AppColors.textSecond),
            const SizedBox(width: 5),
            Text(hint!,
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecond)),
          ]),
        )
      else
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.flip_rounded, size: 13, color: AppColors.textSecond),
            const SizedBox(width: 5),
            Text('tap to flip back',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecond)),
          ]),
        ),
    ]),
  );
}

// ── Rating button ─────────────────────────────────────────────────────────────

class _RatingButton extends StatelessWidget {
  final String             label;
  final String             sublabel;
  final Color              color;
  final int                quality;
  final void Function(int) onTap;

  const _RatingButton({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.quality,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: () => onTap(quality),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 1),
          Text(sublabel,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.65))),
        ]),
      ),
    ),
  );
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final int      count;
  final Color    color;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: color),
    ),
    const SizedBox(width: 12),
    Text(label,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary)),
    const Spacer(),
    Text('$count',
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color)),
  ]);
}