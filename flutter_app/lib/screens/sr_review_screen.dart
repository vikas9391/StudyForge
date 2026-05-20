// lib/screens/sr_review_screen.dart
// Spaced repetition review session.
//
// Shows cards due today one at a time.
// User taps to reveal the answer, then rates recall quality (Again/Hard/Good/Easy).
// Ratings map to SM-2 quality scores: Again=1, Hard=2, Good=3, Easy=5.
// After all cards, shows a completion summary.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import '../core/constants.dart';
import '../models/study_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class SrReviewScreen extends StatefulWidget {
  const SrReviewScreen({super.key});

  @override
  State<SrReviewScreen> createState() => _SrReviewScreenState();
}

class _SrReviewScreenState extends State<SrReviewScreen>
    with SingleTickerProviderStateMixin {
  final _api  = ApiService();
  final _auth = AuthService();

  List<SrSession> _sessions = [];
  List<SrCard>    _queue    = [];           // flat queue of all due cards
  List<String>    _resultIds = [];          // matching result_id for each card

  int  _currentIndex = 0;
  bool _revealed     = false;
  bool _loading      = true;
  bool _submitting   = false;
  String? _error;

  // Stats for summary screen
  int _reviewed = 0;
  int _again    = 0;
  int _hard     = 0;
  int _good     = 0;
  int _easy     = 0;

  // Flip animation
  late AnimationController _flipCtrl;
  late Animation<double>   _flipAnim;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
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

      // Flatten into a single queue
      _queue     = [];
      _resultIds = [];
      for (final s in _sessions) {
        for (final c in s.cards) {
          _queue.add(c);
          _resultIds.add(s.resultId);
        }
      }
      setState(() { _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  SrCard get _current => _queue[_currentIndex];

  Future<void> _rate(int quality) async {
    if (_submitting) return;
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);

    final uid = _auth.userId ?? '';
    try {
      await _api.submitSrReview(
        userId:    uid,
        resultId:  _resultIds[_currentIndex],
        cardIndex: _current.cardIndex,
        quality:   quality,
      );
    } catch (_) {
      // Non-critical — continue the session even if a review fails to save
    }

    // Update stats
    _reviewed++;
    if (quality <= 1)      _again++;
    else if (quality == 2) _hard++;
    else if (quality == 3) _good++;
    else                   _easy++;

    // Advance or finish
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
        leading: BackButton(color: AppColors.textSecond),
        title: Text('Review Due Cards', style: AppText.subheading),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _buildError()
              : _queue.isEmpty
                  ? _buildAllCaughtUp()
                  : _done
                      ? _buildSummary()
                      : _buildReviewCard(),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.accentRed),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center, style: AppText.caption),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _loadDueCards, child: const Text('Retry')),
      ]),
    ),
  );

  Widget _buildAllCaughtUp() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('🎉', style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('All caught up!',
            style: AppText.subheading.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('No cards are due for review today.\nCome back tomorrow!',
            textAlign: TextAlign.center, style: AppText.caption),
      ]),
    ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
  );

  Widget _buildSummary() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 20),
      Text('Session complete! 🎉',
          textAlign: TextAlign.center,
          style: AppText.subheading.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('You reviewed $_reviewed card${_reviewed == 1 ? '' : 's'}.',
          textAlign: TextAlign.center, style: AppText.caption),
      const SizedBox(height: 32),

      // Rating breakdown
      _SummaryRow(label: 'Again', count: _again, color: AppColors.accentRed),
      _SummaryRow(label: 'Hard',  count: _hard,  color: AppColors.accentAmber),
      _SummaryRow(label: 'Good',  count: _good,  color: AppColors.accentGreen),
      _SummaryRow(label: 'Easy',  count: _easy,  color: AppColors.accentBlue),

      const Spacer(),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGrad,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(
            child: Text('Done', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15,
            )),
          ),
        ),
      ),
    ]).animate().fadeIn(),
  );

  Widget _buildReviewCard() {
    final card = _current;
    final progress = (_currentIndex + 1) / _queue.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.border,
            color: AppColors.primary,
            minHeight: 4,
          ),
        ),

        const SizedBox(height: 24),

        // Flip card
        Expanded(
          child: GestureDetector(
            onTap: _revealed ? null : _reveal,
            child: AnimatedBuilder(
              animation: _flipAnim,
              builder: (_, __) {
                final angle  = _flipAnim.value * math.pi;
                final isBack = _flipAnim.value >= 0.5;
                final faceAngle = isBack ? angle - math.pi : angle;

                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(faceAngle),
                  child: isBack
                      ? _CardFace(
                          label: 'ANSWER',
                          text: card.back,
                          color: AppColors.accentGreen,
                          isBack: true,
                        )
                      : _CardFace(
                          label: 'TERM',
                          text: card.front,
                          color: AppColors.primary,
                          isBack: false,
                          hint: 'Tap to reveal answer',
                        ),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Rating buttons — shown only after reveal
        AnimatedOpacity(
          opacity: _revealed ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_revealed,
            child: Column(children: [
              Text('How well did you remember?',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(children: [
                _RatingButton(label: 'Again', sublabel: 'Forgot',
                    color: AppColors.accentRed,    quality: 1, onTap: _rate),
                const SizedBox(width: 8),
                _RatingButton(label: 'Hard',  sublabel: 'Difficult',
                    color: AppColors.accentAmber,  quality: 2, onTap: _rate),
                const SizedBox(width: 8),
                _RatingButton(label: 'Good',  sublabel: 'Correct',
                    color: AppColors.accentGreen,  quality: 3, onTap: _rate),
                const SizedBox(width: 8),
                _RatingButton(label: 'Easy',  sublabel: 'Perfect',
                    color: AppColors.accentBlue,   quality: 5, onTap: _rate),
              ]),
            ]),
          ),
        ),

        const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
      color: isBack ? AppColors.accentGreen.withOpacity(0.05) : AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withOpacity(0.35), width: 1.5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: AppText.label.copyWith(color: color, fontWeight: FontWeight.w700)),
      ),
      const Spacer(),
      Text(text,
          style: AppText.subheading.copyWith(
            height: 1.5,
            fontWeight: isBack ? FontWeight.w400 : FontWeight.w700,
          )),
      const Spacer(),
      if (hint != null)
        Center(
          child: Text(hint!,
              style: AppText.label.copyWith(color: AppColors.textMuted)),
        ),
    ]),
  );
}

class _RatingButton extends StatelessWidget {
  final String   label;
  final String   sublabel;
  final Color    color;
  final int      quality;
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          Text(sublabel,
              style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
        ]),
      ),
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;

  const _SummaryRow({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 12),
      Text(label, style: AppText.body),
      const Spacer(),
      Text('$count', style: AppText.body.copyWith(
          color: color, fontWeight: FontWeight.w700)),
    ]),
  );
}